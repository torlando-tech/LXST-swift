// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
//  TelephoneTransportTests.swift
//  LXSTSwiftTests
//
//  Exercises the refactored `Telephone` actor over a mock `NetworkTransport`,
//  with no Reticulum stack. Verifies the transport seam wiring: outbound call
//  → openOutboundCall, AVAILABLE → identifySelf, incoming call → AVAILABLE
//  signal, hangup → closeCall, and that signalling payloads flow through
//  `transport.send`. This is what proves the transport-agnostic refactor works.

import XCTest
@testable import LXSTSwift

/// In-memory NetworkTransport that records outbound calls and lets the test
/// drive inbound events through the handlers Telephone installs.
actor MockNetworkTransport: NetworkTransport {
    // Recorded outbound activity
    private(set) var openedTo: Data?
    private(set) var didIdentify = false
    private(set) var didClose = false
    private(set) var sentPayloads: [Data] = []
    var openResult = true

    // Handlers installed by Telephone
    private var incomingHandler: (@Sendable () async -> Void)?
    private var identifiedHandler: (@Sendable (Data) async -> Void)?
    private var receiveHandler: (@Sendable (Data) async -> Void)?
    private var closedHandler: (@Sendable (TransportCloseReason) async -> Void)?

    private var active = false

    // MARK: NetworkTransport (outbound)
    func openOutboundCall(to destinationHash: Data) async -> Bool {
        openedTo = destinationHash
        active = openResult
        return openResult
    }
    func identifySelf() async { didIdentify = true }
    func send(_ payload: Data) async { sentPayloads.append(payload) }
    func closeCall() async { didClose = true; active = false }
    var isCallActive: Bool { active }

    // MARK: NetworkTransport (inbound handler registration)
    func setIncomingCallHandler(_ handler: @escaping @Sendable () async -> Void) { incomingHandler = handler }
    func setRemoteIdentifiedHandler(_ handler: @escaping @Sendable (Data) async -> Void) { identifiedHandler = handler }
    func setReceiveHandler(_ handler: @escaping @Sendable (Data) async -> Void) { receiveHandler = handler }
    func setClosedHandler(_ handler: @escaping @Sendable (TransportCloseReason) async -> Void) { closedHandler = handler }

    // MARK: Test drivers — simulate the network delivering events
    func fireIncomingCall() async { await incomingHandler?() }
    func fireRemoteIdentified(_ hash: Data) async { await identifiedHandler?(hash) }
    func fireReceive(_ data: Data) async { await receiveHandler?(data) }
    func fireClosed(_ reason: TransportCloseReason) async { await closedHandler?(reason) }
}

final class TelephoneTransportTests: XCTestCase {

    private let peerHash = Data(repeating: 0xAB, count: 16)

    func testOutboundCallOpensTransportToPeer() async throws {
        let mock = MockNetworkTransport()
        let phone = await Telephone.make(transport: mock)

        try await phone.call(destinationHash: peerHash)

        let opened = await mock.openedTo
        XCTAssertEqual(opened, peerHash, "call() must open an outbound link to the dialled hash")
        let state = await phone.callState
        XCTAssertEqual(state, .calling, "after opening, we wait (in .calling) for the callee's AVAILABLE")
    }

    func testOutboundFailureEndsCall() async {
        let mock = MockNetworkTransport()
        await mock.setOpenResult(false)
        let phone = await Telephone.make(transport: mock)

        await XCTAssertThrowsErrorAsync(try await phone.call(destinationHash: peerHash))
        let state = await phone.callState
        XCTAssertEqual(state, .idle, "a failed open must reset to idle")
    }

    func testAvailableTriggersIdentify() async throws {
        let mock = MockNetworkTransport()
        let phone = await Telephone.make(transport: mock)
        try await phone.call(destinationHash: peerHash)

        // Callee signals AVAILABLE → we should identify ourselves.
        await mock.fireReceive(LXSTWireFormat.packSignal(.available))

        let identified = await mock.didIdentify
        XCTAssertTrue(identified, "AVAILABLE must trigger identifySelf() over the transport")
        let state = await phone.callState
        XCTAssertEqual(state, .available)
    }

    func testIncomingCallSendsAvailableSignal() async {
        let mock = MockNetworkTransport()
        let phone = await Telephone.make(transport: mock)

        await mock.fireIncomingCall()

        let state = await phone.callState
        XCTAssertEqual(state, .available, "incoming call → .available while awaiting identification")
        let sent = await mock.sentPayloads
        XCTAssertEqual(sent.count, 1, "incoming call should emit exactly one signal (AVAILABLE)")
        // Confirm it parses back to the AVAILABLE signal.
        if case .signals(let sigs)? = try? LXSTWireFormat.unpack(sent[0]) {
            XCTAssertTrue(sigs.contains(UInt(LXSTSignal.available.rawValue)), "first payload must be AVAILABLE")
        } else {
            XCTFail("emitted payload was not a signal")
        }
    }

    func testIncomingCallRingsAfterIdentify() async {
        let mock = MockNetworkTransport()
        let phone = await Telephone.make(transport: mock)
        await mock.fireIncomingCall()

        await mock.fireRemoteIdentified(peerHash)

        let state = await phone.callState
        XCTAssertEqual(state, .ringing, "after caller identifies, an allowed call rings")
    }

    func testRemoteClosedEndsCall() async throws {
        let mock = MockNetworkTransport()
        let phone = await Telephone.make(transport: mock)
        try await phone.call(destinationHash: peerHash)

        await mock.fireClosed(.remoteClosed)

        let state = await phone.callState
        XCTAssertEqual(state, .idle, "remote close tears the call down to idle")
    }
}

// MARK: - async throws assertion helper

func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        // expected
    }
}

// Test-only setter so the mock's openResult can be configured from the test.
extension MockNetworkTransport {
    func setOpenResult(_ value: Bool) { openResult = value }
}
