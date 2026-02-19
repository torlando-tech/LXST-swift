//
//  LinkSource.swift
//  LXSTSwift
//
//  Stub link source matching Python LXST Network.py LinkSource class.
//  Receives decoded audio frames from the remote peer via link packets.
//

import Foundation

/// LinkSource receives audio frames from a remote peer over a Reticulum link.
///
/// Python `LinkSource` (Network.py:98) sets `link.set_packet_callback(_packet)`
/// to receive incoming packets, unpacks msgpack, detects codec from header byte,
/// and delivers decoded frames to a sink.
public actor LinkSource {

    /// Current codec type detected from incoming frames.
    public private(set) var currentCodecType: LXSTCodecType = .null

    /// Whether the source is active.
    public private(set) var isRunning: Bool = false

    /// Callback for received decoded frames (Phase 4: will deliver to Mixer/Sink).
    private var frameCallback: (@Sendable (LXSTCodecType, Data) async -> Void)?

    /// Signal callback for forwarding signals to the Telephone.
    private var signalCallback: (@Sendable ([UInt]) async -> Void)?

    public init() {}

    /// Set callback for received audio frames.
    public func setFrameCallback(_ callback: @escaping @Sendable (LXSTCodecType, Data) async -> Void) {
        self.frameCallback = callback
    }

    /// Set callback for received signals.
    public func setSignalCallback(_ callback: @escaping @Sendable ([UInt]) async -> Void) {
        self.signalCallback = callback
    }

    /// Start receiving.
    public func start() {
        isRunning = true
    }

    /// Stop receiving.
    public func stop() {
        isRunning = false
    }

    /// Handle an incoming packet (set as link packet callback).
    ///
    /// Python `_packet()` (Network.py:109): Unpacks msgpack, routes frames
    /// and signals. Detects codec changes from header byte.
    ///
    /// - Parameters:
    ///   - data: Decrypted packet data
    ///   - packet: The original packet
    public func handlePacket(data: Data, packet: Packet) async {
        guard isRunning else { return }

        guard let parsed = try? LXSTWireFormat.unpack(data) else { return }

        switch parsed {
        case .frame(let codecHeader, let audioData):
            if let codecType = LXSTCodecType(rawValue: codecHeader) {
                if codecType != currentCodecType {
                    currentCodecType = codecType
                }
                await frameCallback?(codecType, audioData)
            }

        case .signals(let signals):
            await signalCallback?(signals)

        case .mixed(let signals, let codecHeader, let audioData):
            // Handle both
            await signalCallback?(signals)
            if let codecType = LXSTCodecType(rawValue: codecHeader) {
                if codecType != currentCodecType {
                    currentCodecType = codecType
                }
                await frameCallback?(codecType, audioData)
            }
        }
    }
}
