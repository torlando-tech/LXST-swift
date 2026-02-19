//
//  AudioCodec.swift
//  LXSTSwift
//
//  Protocol for audio codecs matching Python LXST Codecs/Codec.py.
//

import Foundation

/// Protocol for audio codecs that encode/decode Int16 PCM frames.
public protocol AudioCodec: Sendable {
    /// The codec type identifier for wire format headers.
    var codecType: LXSTCodecType { get }

    /// Number of audio channels.
    var channels: Int { get }

    /// Input sample rate in Hz.
    var inputRate: Int { get }

    /// Output sample rate in Hz.
    var outputRate: Int { get }

    /// Encode PCM Int16 samples to compressed data.
    ///
    /// - Parameter samples: Array of Int16 PCM samples
    /// - Returns: Encoded audio data (without codec header byte)
    func encode(_ samples: [Int16]) throws -> Data

    /// Decode compressed data to PCM Int16 samples.
    ///
    /// - Parameter data: Encoded audio data (without codec header byte)
    /// - Returns: Array of Int16 PCM samples
    func decode(_ data: Data) throws -> [Int16]
}
