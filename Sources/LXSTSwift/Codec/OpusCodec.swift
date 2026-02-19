//
//  OpusCodec.swift
//  LXSTSwift
//
//  Swift wrapper for libopus matching Python LXST Codecs/Opus.py.
//  Provides encode/decode for int16 PCM samples.
//

import Foundation

#if canImport(COpus)
import COpus

/// Opus codec wrapper matching Python LXST Opus class.
///
/// Wraps libopus encoder and decoder for a given OpusProfile.
/// Handles creation, configuration, encode/decode, and cleanup.
///
/// Python reference: `Codecs/Opus.py`
public final class OpusCodec: AudioCodec, @unchecked Sendable {

    public let codecType: LXSTCodecType = .opus
    public let channels: Int
    public let inputRate: Int
    public let outputRate: Int

    private var encoder: OpaquePointer?
    private var decoder: OpaquePointer?
    private let profile: OpusProfile
    private let maxFrameSize: Int

    /// Create an Opus codec for the given profile.
    ///
    /// - Parameter profile: The Opus profile (determines sample rate, channels, application)
    /// - Throws: `LXSTError.codecError` if encoder/decoder creation fails
    public init(profile: OpusProfile) throws {
        self.profile = profile
        self.channels = profile.channels
        self.inputRate = profile.sampleRate
        self.outputRate = profile.sampleRate

        // Max samples per channel for a 60ms frame at 48kHz
        self.maxFrameSize = 48000 * 60 / 1000 // 2880

        let application: Int32 = profile.application == "voip"
            ? OPUS_APPLICATION_VOIP
            : OPUS_APPLICATION_AUDIO

        var error: Int32 = 0
        encoder = opus_encoder_create(Int32(profile.sampleRate), Int32(channels), application, &error)
        guard error == OPUS_OK, encoder != nil else {
            throw LXSTError.codecError("Opus encoder creation failed: \(error)")
        }

        // Set bitrate ceiling
        opus_encoder_ctl(encoder!, OPUS_SET_BITRATE_REQUEST, Int32(profile.bitrateCeiling))

        // Set complexity (10 = highest quality)
        opus_encoder_ctl(encoder!, OPUS_SET_COMPLEXITY_REQUEST, Int32(10))

        decoder = opus_decoder_create(Int32(profile.sampleRate), Int32(channels), &error)
        guard error == OPUS_OK, decoder != nil else {
            if let enc = encoder { opus_encoder_destroy(enc) }
            throw LXSTError.codecError("Opus decoder creation failed: \(error)")
        }
    }

    deinit {
        if let enc = encoder { opus_encoder_destroy(enc) }
        if let dec = decoder { opus_decoder_destroy(dec) }
    }

    /// Encode PCM samples to Opus.
    ///
    /// - Parameter samples: Interleaved int16 PCM samples (length = frameSize * channels)
    /// - Returns: Encoded Opus data
    /// - Throws: `LXSTError.codecError` on encoding failure
    public func encode(_ samples: [Int16]) throws -> Data {
        guard let enc = encoder else {
            throw LXSTError.codecError("Encoder not initialized")
        }

        let frameSize = samples.count / channels

        // Calculate max output bytes from bitrate ceiling
        let frameDurationMs = Double(frameSize) / Double(inputRate) * 1000.0
        let maxBytes = profile.maxBytesPerFrame(frameDurationMs: frameDurationMs)
        let outputBufferSize = max(maxBytes, 4000)

        var outputBuffer = [UInt8](repeating: 0, count: outputBufferSize)
        let encodedLength = samples.withUnsafeBufferPointer { pcmPtr in
            opus_encode(enc, pcmPtr.baseAddress, Int32(frameSize),
                       &outputBuffer, Int32(outputBufferSize))
        }

        guard encodedLength > 0 else {
            throw LXSTError.codecError("Opus encode failed: \(encodedLength)")
        }

        return Data(outputBuffer.prefix(Int(encodedLength)))
    }

    /// Decode Opus data to PCM samples.
    ///
    /// - Parameter data: Encoded Opus data
    /// - Returns: Decoded interleaved int16 PCM samples
    /// - Throws: `LXSTError.codecError` on decoding failure
    public func decode(_ data: Data) throws -> [Int16] {
        guard let dec = decoder else {
            throw LXSTError.codecError("Decoder not initialized")
        }

        var pcmBuffer = [Int16](repeating: 0, count: maxFrameSize * channels)
        let decodedSamples = data.withUnsafeBytes { rawPtr -> Int32 in
            let bytes = rawPtr.bindMemory(to: UInt8.self)
            return opus_decode(dec, bytes.baseAddress, Int32(data.count),
                             &pcmBuffer, Int32(maxFrameSize), 0)
        }

        guard decodedSamples > 0 else {
            throw LXSTError.codecError("Opus decode failed: \(decodedSamples)")
        }

        return Array(pcmBuffer.prefix(Int(decodedSamples) * channels))
    }
}

#else

/// Opus codec stub when COpus is not available.
///
/// Throws `.codecError` on all operations.
public final class OpusCodec: AudioCodec, @unchecked Sendable {
    public let codecType: LXSTCodecType = .opus
    public let channels: Int
    public let inputRate: Int
    public let outputRate: Int

    public init(profile: OpusProfile) throws {
        self.channels = profile.channels
        self.inputRate = profile.sampleRate
        self.outputRate = profile.sampleRate
        throw LXSTError.codecError("Opus codec not available: COpus library not linked")
    }

    public func encode(_ samples: [Int16]) throws -> Data {
        throw LXSTError.codecError("Opus codec not available")
    }

    public func decode(_ data: Data) throws -> [Int16] {
        throw LXSTError.codecError("Opus codec not available")
    }
}

#endif
