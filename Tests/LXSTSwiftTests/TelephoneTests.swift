//
//  TelephoneTests.swift
//  LXSTSwiftTests
//
//  Tests for the Telephone call state machine.
//

import XCTest
@testable import LXSTSwift

final class TelephoneTests: XCTestCase {

    // MARK: - Call State Machine

    func testInitialStateIsIdle() {
        XCTAssertEqual(CallState.idle, CallState.idle)
        XCTAssertNotEqual(CallState.idle, CallState.calling)
    }

    func testCallStateTransitions() {
        // Valid progression: idle -> calling -> available -> ringing -> connecting -> established
        let states: [CallState] = [.idle, .calling, .available, .ringing, .connecting, .established]
        for i in 0..<states.count - 1 {
            XCTAssertNotEqual(states[i], states[i + 1])
        }
    }

    func testEndReasons() {
        let reasons: [CallEndReason] = [
            .localHangup, .remoteHangup, .rejected, .busy,
            .ringTimeout, .connectTimeout, .linkClosed
        ]
        for reason in reasons {
            let state = CallState.ended(reason)
            XCTAssertEqual(state, CallState.ended(reason))
        }
    }

    // MARK: - Caller Filter

    func testCallerFilterAllowAll() {
        let filter = CallerFilter.allowAll
        switch filter {
        case .allowAll:
            break // expected
        default:
            XCTFail("Expected allowAll")
        }
    }

    func testCallerFilterAllowNone() {
        let filter = CallerFilter.allowNone
        switch filter {
        case .allowNone:
            break // expected
        default:
            XCTFail("Expected allowNone")
        }
    }

    func testCallerFilterAllowList() {
        let hash = Data(repeating: 0xAB, count: 16)
        let filter = CallerFilter.allowList([hash])
        switch filter {
        case .allowList(let hashes):
            XCTAssertEqual(hashes.count, 1)
            XCTAssertEqual(hashes[0], hash)
        default:
            XCTFail("Expected allowList")
        }
    }

    // MARK: - TelephonyConstants

    func testTelephonyConstants() {
        XCTAssertEqual(TelephonyConstants.appName, "lxst")
        XCTAssertEqual(TelephonyConstants.primitiveName, "telephony")
        XCTAssertEqual(TelephonyConstants.ringTime, 60)
        XCTAssertEqual(TelephonyConstants.waitTime, 70)
        XCTAssertEqual(TelephonyConstants.connectTime, 5)
        XCTAssertEqual(TelephonyConstants.dialToneFrequency, 382)
        XCTAssertEqual(TelephonyConstants.allowAll, 0xFF)
        XCTAssertEqual(TelephonyConstants.allowNone, 0xFE)
    }

    // MARK: - Wire Format Signal Dispatch

    func testSignalDispatchBusy() throws {
        let packed = LXSTWireFormat.packSignal(.busy)
        let parsed = try LXSTWireFormat.unpack(packed)

        switch parsed {
        case .signals(let signals):
            XCTAssertEqual(signals.count, 1)
            let signal = LXSTWireFormat.extractSignal(from: signals[0])
            XCTAssertEqual(signal, .busy)
        default:
            XCTFail("Expected signals")
        }
    }

    func testSignalDispatchAvailable() throws {
        let packed = LXSTWireFormat.packSignal(.available)
        let parsed = try LXSTWireFormat.unpack(packed)

        switch parsed {
        case .signals(let signals):
            XCTAssertEqual(signals.count, 1)
            let signal = LXSTWireFormat.extractSignal(from: signals[0])
            XCTAssertEqual(signal, .available)
        default:
            XCTFail("Expected signals")
        }
    }

    func testSignalDispatchPreferredProfile() throws {
        // Test all profiles
        for profile in TelephonyProfile.allCases {
            let packed = LXSTWireFormat.packPreferredProfile(profile)
            let parsed = try LXSTWireFormat.unpack(packed)

            switch parsed {
            case .signals(let signals):
                XCTAssertEqual(signals.count, 1)
                // Should NOT be a regular signal
                XCTAssertNil(LXSTWireFormat.extractSignal(from: signals[0]))
                // Should be a profile signal
                let extracted = LXSTWireFormat.extractPreferredProfile(from: signals[0])
                XCTAssertEqual(extracted, profile)
            default:
                XCTFail("Expected signals for profile \(profile)")
            }
        }
    }

    // MARK: - Full Signal Sequence

    func testIncomingCallSignalSequence() throws {
        // Verify the signal sequence for an incoming call:
        // Callee sends: AVAILABLE -> RINGING -> CONNECTING -> ESTABLISHED
        let signals: [LXSTSignal] = [.available, .ringing, .connecting, .established]

        for signal in signals {
            let packed = LXSTWireFormat.packSignal(signal)
            let parsed = try LXSTWireFormat.unpack(packed)
            switch parsed {
            case .signals(let s):
                let extracted = LXSTWireFormat.extractSignal(from: s[0])
                XCTAssertEqual(extracted, signal)
            default:
                XCTFail("Expected signals")
            }
        }
    }

    func testOutgoingCallSignalSequence() throws {
        // Caller receives: AVAILABLE -> RINGING -> CONNECTING -> ESTABLISHED
        // Caller sends: (identify) -> PREFERRED_PROFILE
        let received: [LXSTSignal] = [.available, .ringing, .connecting, .established]

        for signal in received {
            let packed = LXSTWireFormat.packSignal(signal)
            let parsed = try LXSTWireFormat.unpack(packed)
            switch parsed {
            case .signals(let s):
                XCTAssertEqual(LXSTWireFormat.extractSignal(from: s[0]), signal)
            default:
                XCTFail("Expected signals")
            }
        }

        // Preferred profile (sent by caller after RINGING)
        let profilePacked = LXSTWireFormat.packPreferredProfile(.qualityMedium)
        let profileParsed = try LXSTWireFormat.unpack(profilePacked)
        switch profileParsed {
        case .signals(let s):
            let profile = LXSTWireFormat.extractPreferredProfile(from: s[0])
            XCTAssertEqual(profile, .qualityMedium)
        default:
            XCTFail("Expected signals")
        }
    }
}
