// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
//
//  Packetizer.swift
//  LXSTSwift
//
//  Stub packetizer matching Python LXST Network.py Packetizer class.
//  Sends encoded audio frames as link DATA packets.
//

import Foundation

/// Packetizer wraps encoded audio frames with their codec header and hands the
/// LXST-wire payload to a send callback. Transport-agnostic: encryption and
/// link transmission are the `NetworkTransport`'s job, not the packetizer's.
///
/// Mirrors Python `Packetizer` (Network.py:49), minus the RNS link — the wire
/// payload `{FIELD_FRAMES: codec_header + frame}` is produced by
/// `LXSTWireFormat.packFrame` and passed on for the transport to send.
public actor Packetizer {

    /// Send callback for transmitting the packed LXST payload.
    private var sendCallback: (@Sendable (Data) async -> Void)?

    /// Whether the packetizer is active.
    public private(set) var isRunning: Bool = false

    public init() {}

    /// Set the send callback for packed-payload transmission.
    public func setSendCallback(_ callback: @escaping @Sendable (Data) async -> Void) {
        self.sendCallback = callback
    }

    /// Start the packetizer.
    public func start() {
        isRunning = true
    }

    /// Stop the packetizer.
    public func stop() {
        isRunning = false
    }

    /// Pack an encoded audio frame with its codec header and emit it.
    ///
    /// - Parameters:
    ///   - codecType: The codec type for the header byte
    ///   - encodedAudio: The encoded audio data
    public func sendFrame(codecType: LXSTCodecType, encodedAudio: Data) async {
        guard isRunning else { return }
        let packetData = LXSTWireFormat.packFrame(codecType: codecType, encodedAudio: encodedAudio)
        await sendCallback?(packetData)
    }
}
