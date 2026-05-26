// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
//  NetworkTransport.swift
//  LXSTSwift
//
//  Network transport abstraction for telephony — the seam that keeps LXSTSwift
//  free of any concrete Reticulum / RNS dependency. Mirrors LXST-kt's
//  `tech.torlando.lxst.telephone.NetworkTransport`.
//
//  Design (from LXST-kt): the LXST library owns the call STATE MACHINE,
//  SIGNALLING wire format (LXSTWireFormat), CODECS, and AUDIO pipeline. The
//  NETWORK — link lifecycle, encryption, packetization, identify, path
//  resolution, incoming-link detection — lives entirely behind this protocol,
//  implemented by the host app (e.g. Columba's PythonNetworkTransport over the
//  Python RNS backend; or a future pure-Swift Reticulum impl).
//
//  Nothing Reticulum-shaped crosses this boundary: peers are `Data` hashes,
//  signals are `Int`, and call payloads are `Data` already packed/unpacked by
//  `LXSTWireFormat`. `Telephone` never sees an Identity / Destination / Link /
//  Packet.

import Foundation

/// Reason a call link ended, surfaced by the transport to `Telephone`.
public enum TransportCloseReason: Sendable, Equatable {
    /// The remote peer closed the link (remote hangup).
    case remoteClosed
    /// The link dropped due to timeout / network failure.
    case linkFailed
}

/// Abstraction over the network layer for LXST telephony.
///
/// `Telephone` drives this; the host app implements it. All methods are async
/// so implementations can bridge to actor-isolated or cross-process backends
/// (e.g. an embedded Python RNS stack).
public protocol NetworkTransport: Sendable {

    // MARK: Outbound (Telephone → network)

    /// Open an outbound call link to `destinationHash` (the peer's
    /// lxst.telephony destination). Resolves a path if needed, establishes the
    /// link, and wires inbound delivery to the handlers below.
    /// Returns `true` once the link is up, `false` on timeout/failure.
    func openOutboundCall(to destinationHash: Data) async -> Bool

    /// Identify the local endpoint to the remote over the active link
    /// (RNS LINKIDENTIFY). Outbound callers identify after the callee signals
    /// AVAILABLE so the callee learns who is calling.
    func identifySelf() async

    /// Send an LXST payload (already packed by `LXSTWireFormat` — a signal,
    /// audio frame, or mixed) over the active link. The transport encrypts and
    /// packetizes; LXSTSwift owns the payload bytes.
    func send(_ payload: Data) async

    /// Tear down the active call link, if any.
    func closeCall() async

    /// Whether a call link is currently active.
    var isCallActive: Bool { get async }

    // MARK: Inbound (network → Telephone, via handlers)

    /// Set the handler fired when a remote peer establishes an inbound call
    /// link to our telephony destination. (The transport owns destination
    /// registration; it knows the local identity.)
    func setIncomingCallHandler(_ handler: @escaping @Sendable () async -> Void) async

    /// Set the handler fired when the remote caller identifies, carrying their
    /// identity hash (RNS LINKIDENTIFY → identity hash bytes).
    func setRemoteIdentifiedHandler(_ handler: @escaping @Sendable (Data) async -> Void) async

    /// Set the handler fired for each decrypted inbound LXST payload (to be
    /// unpacked by `LXSTWireFormat`).
    func setReceiveHandler(_ handler: @escaping @Sendable (Data) async -> Void) async

    /// Set the handler fired when the active link closes.
    func setClosedHandler(_ handler: @escaping @Sendable (TransportCloseReason) async -> Void) async
}
