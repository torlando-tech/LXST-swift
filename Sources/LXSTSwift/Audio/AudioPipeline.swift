//
//  AudioPipeline.swift
//  LXSTSwift
//
//  Audio pipeline matching Python LXST Pipeline.py.
//  Orchestrates source→codec→sink chain for encoding/decoding audio.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.lxst.swift", category: "AudioPipeline")

/// Audio pipeline that connects a source, codec, and sink.
///
/// Matches Python `Pipeline` class. Manages the lifecycle of audio processing:
/// source captures audio, codec encodes/decodes, sink delivers to network or speaker.
///
/// Internally uses Float arrays (range -1.0 to 1.0). Int16 conversion happens
/// at codec boundaries.
public actor AudioPipeline {

    /// Pipeline configuration.
    public struct Config: Sendable {
        public let codecType: LXSTCodecType
        public let sampleRate: Int
        public let channels: Int
        public let frameTimeMs: Int

        public init(codecType: LXSTCodecType, sampleRate: Int, channels: Int, frameTimeMs: Int) {
            self.codecType = codecType
            self.sampleRate = sampleRate
            self.channels = channels
            self.frameTimeMs = frameTimeMs
        }

        /// Create config from a TelephonyProfile.
        public init(profile: TelephonyProfile) {
            self.codecType = profile.codecType
            self.frameTimeMs = profile.frameTimeMs

            switch profile.codecType {
            case .opus:
                let opusProfile = profile.opusProfile!
                self.sampleRate = opusProfile.sampleRate
                self.channels = opusProfile.channels
            case .codec2:
                self.sampleRate = 8000
                self.channels = 1
            default:
                self.sampleRate = 48000
                self.channels = 1
            }
        }

        /// Samples per frame (per channel).
        public var samplesPerFrame: Int {
            sampleRate * frameTimeMs / 1000
        }
    }

    private let config: Config
    private var isRunning = false

    /// Callback that receives encoded audio frames ready for network transmission.
    private var encodedFrameCallback: (@Sendable (LXSTCodecType, Data) async -> Void)?

    /// Callback that receives decoded float samples ready for playback.
    private var decodedSamplesCallback: (@Sendable ([Float], Int, Int) async -> Void)?

    /// Jitter buffer for smoothing receive-side timing jitter.
    private var jitterBuffer: JitterBuffer?

    /// Periodic playout task that dequeues from the jitter buffer.
    private var playoutTask: Task<Void, Never>?

    /// Active codec reference for PLC generation during underruns.
    private var activeCodec: (any AudioCodec)?

    public init(config: Config) {
        self.config = config
    }

    /// Set callback for encoded frames (output of encode pipeline).
    public func setEncodedFrameCallback(
        _ callback: @escaping @Sendable (LXSTCodecType, Data) async -> Void
    ) {
        self.encodedFrameCallback = callback
    }

    /// Set callback for decoded samples (output of decode pipeline).
    /// Parameters: (samples: [Float], sampleRate: Int, channels: Int)
    public func setDecodedSamplesCallback(
        _ callback: @escaping @Sendable ([Float], Int, Int) async -> Void
    ) {
        self.decodedSamplesCallback = callback
    }

    /// Start the pipeline with a codec for PLC and jitter buffering.
    ///
    /// - Parameter codec: The active audio codec (used for PLC on underrun)
    public func start(codec: any AudioCodec) {
        isRunning = true
        self.activeCodec = codec
        let target = playoutTargetDepth
        self.jitterBuffer = JitterBuffer(targetDepth: target, maxDepth: target * 3)
        startPlayoutLoop()
        logger.info("[PIPELINE] Started with codec at \(self.config.sampleRate)Hz, jitter target=\(target)")
    }

    /// Start the pipeline without jitter buffering (legacy path).
    public func start() {
        isRunning = true
        logger.info("[PIPELINE] Started with codec at \(self.config.sampleRate)Hz")
    }

    public func stop() {
        isRunning = false
        playoutTask?.cancel()
        playoutTask = nil
        activeCodec = nil
        jitterBuffer = nil
        logger.info("[PIPELINE] Stopped")
    }

    /// Computed target depth based on frame time.
    private var playoutTargetDepth: Int {
        switch config.frameTimeMs {
        case ...10: return 4   // 40ms total
        case ...20: return 3   // 60ms total
        case ...60: return 3   // 180ms total
        default:    return 2   // high-latency profiles
        }
    }

    /// Process captured float samples through the encode pipeline.
    ///
    /// Float samples → Int16 → codec.encode() → encoded frame callback
    public func processCapture(_ samples: [Float], codec: any AudioCodec) async {
        guard isRunning else { return }

        let int16Samples = floatToInt16(samples)
        do {
            let encoded = try codec.encode(int16Samples)
            await encodedFrameCallback?(config.codecType, encoded)
        } catch {
            logger.error("[PIPELINE] Encode error: \(error)")
        }
    }

    /// Process received encoded data through the decode pipeline.
    ///
    /// When a jitter buffer is active, decoded frames are enqueued for playout.
    /// Otherwise, frames are delivered directly to the callback (legacy path).
    public func processReceived(_ data: Data, codec: any AudioCodec) async {
        guard isRunning else {
            logger.error("[PIPELINE] processReceived called but isRunning=false")
            return
        }

        do {
            let int16Samples = try codec.decode(data)
            let floatSamples = int16ToFloat(int16Samples)

            if let jitterBuffer {
                await jitterBuffer.enqueue(floatSamples)
                let depth = await jitterBuffer.depth
                let primed = await jitterBuffer.isPrimed
                if depth == 1 || (depth % 10 == 0) {
                    logger.error("[PIPELINE] Jitter depth=\(depth, privacy: .public) primed=\(primed, privacy: .public) samples=\(floatSamples.count, privacy: .public)")
                }
            } else {
                await decodedSamplesCallback?(floatSamples, config.sampleRate, config.channels)
            }
        } catch {
            logger.error("[PIPELINE] Decode error: \(error)")
        }
    }

    // MARK: - Playout Loop

    /// Start the periodic playout loop that dequeues from the jitter buffer.
    private func startPlayoutLoop() {
        let intervalNs = UInt64(config.frameTimeMs) * 1_000_000
        playoutTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let samples = await self.jitterBuffer?.dequeue() {
                    await self.decodedSamplesCallback?(
                        samples, self.config.sampleRate, self.config.channels)
                } else if await (self.jitterBuffer?.isPrimed ?? false) {
                    let plc = await self.generatePLC()
                    await self.decodedSamplesCallback?(
                        plc, self.config.sampleRate, self.config.channels)
                }
                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }
    }

    /// Generate PLC samples from the active codec, or silence as fallback.
    private func generatePLC() -> [Float] {
        let frameSize = config.samplesPerFrame
        if let codec = activeCodec,
           let plc = codec.decodePLC(frameSize: frameSize) {
            return int16ToFloat(plc)
        }
        return [Float](repeating: 0, count: frameSize * config.channels)
    }
}

// MARK: - Sample Conversion

/// Convert Float samples (-1.0...1.0) to Int16.
func floatToInt16(_ samples: [Float]) -> [Int16] {
    samples.map { sample in
        let clamped = max(-1.0, min(1.0, sample))
        return Int16(clamped * Float(Int16.max))
    }
}

/// Convert Int16 samples to Float (-1.0...1.0).
func int16ToFloat(_ samples: [Int16]) -> [Float] {
    samples.map { Float($0) / Float(Int16.max) }
}
