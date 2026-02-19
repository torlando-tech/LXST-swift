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

    public func start() {
        isRunning = true
        logger.info("[PIPELINE] Started with codec at \(self.config.sampleRate)Hz")
    }

    public func stop() {
        isRunning = false
        logger.info("[PIPELINE] Stopped")
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
    /// Encoded data → codec.decode() → Int16 → Float → decoded samples callback
    public func processReceived(_ data: Data, codec: any AudioCodec) async {
        guard isRunning else { return }

        do {
            let int16Samples = try codec.decode(data)
            let floatSamples = int16ToFloat(int16Samples)
            await decodedSamplesCallback?(floatSamples, config.sampleRate, config.channels)
        } catch {
            logger.error("[PIPELINE] Decode error: \(error)")
        }
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
