// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
//
//  LXSTWireFormatTests.swift
//  LXSTSwiftTests
//
//  Wire format round-trip tests verifying Python interop.
//

import XCTest
@testable import LXSTSwift

final class LXSTWireFormatTests: XCTestCase {

    // MARK: - Signal Round-Trip

    func testSignalPackUnpack() throws {
        for signal in LXSTSignal.allCases {
            let packed = LXSTWireFormat.packSignal(signal)
            let parsed = try LXSTWireFormat.unpack(packed)

            switch parsed {
            case .signals(let signals):
                XCTAssertEqual(signals, [UInt(signal.rawValue)],
                               "Signal \(signal) round-trip failed")
            default:
                XCTFail("Expected .signals, got \(parsed)")
            }
        }
    }

    // MARK: - Preferred Profile Round-Trip

    func testPreferredProfilePackUnpack() throws {
        for profile in TelephonyProfile.allCases {
            let packed = LXSTWireFormat.packPreferredProfile(profile)
            let parsed = try LXSTWireFormat.unpack(packed)

            switch parsed {
            case .signals(let signals):
                XCTAssertEqual(signals.count, 1)
                // Python: signal = PREFERRED_PROFILE + profile_byte
                let expected = UInt(LXSTSignal.preferredProfile) + UInt(profile.rawValue)
                XCTAssertEqual(signals[0], expected)
                let extracted = LXSTWireFormat.extractPreferredProfile(from: signals[0])
                XCTAssertEqual(extracted, profile,
                               "Profile \(profile) round-trip failed")
            default:
                XCTFail("Expected .signals, got \(parsed)")
            }
        }
    }

    // MARK: - Frame Round-Trip

    func testFramePackUnpack() throws {
        let testAudio = Data([0x01, 0x02, 0x03, 0x04, 0x05])

        for codecType in LXSTCodecType.allCases {
            let packed = LXSTWireFormat.packFrame(codecType: codecType, encodedAudio: testAudio)
            let parsed = try LXSTWireFormat.unpack(packed)

            switch parsed {
            case .frame(let header, let audio):
                XCTAssertEqual(header, codecType.rawValue,
                               "Codec type \(codecType) header mismatch")
                XCTAssertEqual(audio, testAudio,
                               "Audio data mismatch for \(codecType)")
            default:
                XCTFail("Expected .frame, got \(parsed)")
            }
        }
    }

    // MARK: - Invalid Data

    func testInvalidDataThrows() {
        // Empty data
        XCTAssertThrowsError(try LXSTWireFormat.unpack(Data()))

        // Non-msgpack data
        XCTAssertThrowsError(try LXSTWireFormat.unpack(Data([0xFF, 0xFE, 0xFD])))

        // Msgpack but not a map
        let arrayPack = packMsgPack(.array([.uint(1)]))
        XCTAssertThrowsError(try LXSTWireFormat.unpack(arrayPack))
    }

    // MARK: - Constants Verification

    func testSignallingConstants() {
        XCTAssertEqual(LXSTField.signalling, 0x00)
        XCTAssertEqual(LXSTField.frames, 0x01)
    }

    func testCodecTypeConstants() {
        XCTAssertEqual(LXSTCodecType.null.rawValue, 0xFF)
        XCTAssertEqual(LXSTCodecType.raw.rawValue, 0x00)
        XCTAssertEqual(LXSTCodecType.opus.rawValue, 0x01)
        XCTAssertEqual(LXSTCodecType.codec2.rawValue, 0x02)
    }

    func testSignalConstants() {
        XCTAssertEqual(LXSTSignal.busy.rawValue, 0x00)
        XCTAssertEqual(LXSTSignal.rejected.rawValue, 0x01)
        XCTAssertEqual(LXSTSignal.calling.rawValue, 0x02)
        XCTAssertEqual(LXSTSignal.available.rawValue, 0x03)
        XCTAssertEqual(LXSTSignal.ringing.rawValue, 0x04)
        XCTAssertEqual(LXSTSignal.connecting.rawValue, 0x05)
        XCTAssertEqual(LXSTSignal.established.rawValue, 0x06)
        XCTAssertEqual(LXSTSignal.preferredProfile, 0xFF)
    }

    func testProfileConstants() {
        XCTAssertEqual(TelephonyProfile.bandwidthUltraLow.rawValue, 0x10)
        XCTAssertEqual(TelephonyProfile.bandwidthVeryLow.rawValue, 0x20)
        XCTAssertEqual(TelephonyProfile.bandwidthLow.rawValue, 0x30)
        XCTAssertEqual(TelephonyProfile.qualityMedium.rawValue, 0x40)
        XCTAssertEqual(TelephonyProfile.qualityHigh.rawValue, 0x50)
        XCTAssertEqual(TelephonyProfile.qualityMax.rawValue, 0x60)
        XCTAssertEqual(TelephonyProfile.latencyLow.rawValue, 0x70)
        XCTAssertEqual(TelephonyProfile.latencyUltraLow.rawValue, 0x80)
    }

    func testCodec2ModeConstants() {
        XCTAssertEqual(Codec2Mode.codec2_700C.rawValue, 0x00)
        XCTAssertEqual(Codec2Mode.codec2_1200.rawValue, 0x01)
        XCTAssertEqual(Codec2Mode.codec2_1300.rawValue, 0x02)
        XCTAssertEqual(Codec2Mode.codec2_1400.rawValue, 0x03)
        XCTAssertEqual(Codec2Mode.codec2_1600.rawValue, 0x04)
        XCTAssertEqual(Codec2Mode.codec2_2400.rawValue, 0x05)
        XCTAssertEqual(Codec2Mode.codec2_3200.rawValue, 0x06)
    }

    func testOpusProfileConstants() {
        XCTAssertEqual(OpusProfile.voiceLow.rawValue, 0x00)
        XCTAssertEqual(OpusProfile.voiceMedium.rawValue, 0x01)
        XCTAssertEqual(OpusProfile.voiceHigh.rawValue, 0x02)
        XCTAssertEqual(OpusProfile.voiceMax.rawValue, 0x03)
        XCTAssertEqual(OpusProfile.audioMin.rawValue, 0x04)
        XCTAssertEqual(OpusProfile.audioLow.rawValue, 0x05)
        XCTAssertEqual(OpusProfile.audioMedium.rawValue, 0x06)
        XCTAssertEqual(OpusProfile.audioHigh.rawValue, 0x07)
        XCTAssertEqual(OpusProfile.audioMax.rawValue, 0x08)
    }

    // MARK: - Profile Properties

    func testProfileCodecMapping() {
        XCTAssertEqual(TelephonyProfile.bandwidthUltraLow.codecType, .codec2)
        XCTAssertEqual(TelephonyProfile.bandwidthVeryLow.codecType, .codec2)
        XCTAssertEqual(TelephonyProfile.bandwidthLow.codecType, .codec2)
        XCTAssertEqual(TelephonyProfile.qualityMedium.codecType, .opus)
        XCTAssertEqual(TelephonyProfile.qualityHigh.codecType, .opus)
        XCTAssertEqual(TelephonyProfile.qualityMax.codecType, .opus)
        XCTAssertEqual(TelephonyProfile.latencyLow.codecType, .opus)
        XCTAssertEqual(TelephonyProfile.latencyUltraLow.codecType, .opus)
    }

    func testProfileFrameTimes() {
        XCTAssertEqual(TelephonyProfile.bandwidthUltraLow.frameTimeMs, 400)
        XCTAssertEqual(TelephonyProfile.bandwidthVeryLow.frameTimeMs, 320)
        XCTAssertEqual(TelephonyProfile.bandwidthLow.frameTimeMs, 200)
        XCTAssertEqual(TelephonyProfile.qualityMedium.frameTimeMs, 60)
        XCTAssertEqual(TelephonyProfile.qualityHigh.frameTimeMs, 60)
        XCTAssertEqual(TelephonyProfile.qualityMax.frameTimeMs, 60)
        XCTAssertEqual(TelephonyProfile.latencyLow.frameTimeMs, 20)
        XCTAssertEqual(TelephonyProfile.latencyUltraLow.frameTimeMs, 10)
    }

    func testOpusProfileProperties() {
        XCTAssertEqual(OpusProfile.voiceLow.sampleRate, 8000)
        XCTAssertEqual(OpusProfile.voiceLow.channels, 1)
        XCTAssertEqual(OpusProfile.voiceLow.application, "voip")
        XCTAssertEqual(OpusProfile.voiceLow.bitrateCeiling, 6000)
        XCTAssertEqual(OpusProfile.voiceMax.sampleRate, 48000)
        XCTAssertEqual(OpusProfile.voiceMax.channels, 2)
        XCTAssertEqual(OpusProfile.voiceMax.bitrateCeiling, 32000)
        XCTAssertEqual(OpusProfile.audioMax.sampleRate, 48000)
        XCTAssertEqual(OpusProfile.audioMax.channels, 2)
        XCTAssertEqual(OpusProfile.audioMax.application, "audio")
        XCTAssertEqual(OpusProfile.audioMax.bitrateCeiling, 128000)
    }

    func testOpusMaxBytesPerFrame() {
        XCTAssertEqual(OpusProfile.voiceMedium.maxBytesPerFrame(frameDurationMs: 60), 60)
        XCTAssertEqual(OpusProfile.voiceMedium.maxBytesPerFrame(frameDurationMs: 20), 20)
    }

    // MARK: - NullCodec Round-Trip

    func testNullCodecRoundTrip() throws {
        let codec = NullCodec()
        XCTAssertEqual(codec.codecType, .null)

        let samples: [Int16] = [0, 1000, -1000, Int16.max, Int16.min]
        let encoded = try codec.encode(samples)
        let decoded = try codec.decode(encoded)
        XCTAssertEqual(decoded, samples)
    }

    func testNullCodecOddLengthThrows() {
        let codec = NullCodec()
        XCTAssertThrowsError(try codec.decode(Data([0x01, 0x02, 0x03])))
    }

    // MARK: - Call State

    func testCallStateEquality() {
        XCTAssertEqual(CallState.idle, CallState.idle)
        XCTAssertEqual(CallState.established, CallState.established)
        XCTAssertNotEqual(CallState.idle, CallState.calling)
        XCTAssertEqual(CallState.ended(.localHangup), CallState.ended(.localHangup))
        XCTAssertNotEqual(CallState.ended(.localHangup), CallState.ended(.remoteHangup))
    }

    // MARK: - Profile Next Rotation

    func testProfileNextRotation() {
        XCTAssertEqual(TelephonyProfile.bandwidthUltraLow.nextProfile, .bandwidthVeryLow)
        XCTAssertEqual(TelephonyProfile.latencyUltraLow.nextProfile, .bandwidthUltraLow)
    }

    // MARK: - Signal Extraction

    func testExtractRegularSignal() {
        XCTAssertEqual(LXSTWireFormat.extractSignal(from: 0x03), .available)
        XCTAssertEqual(LXSTWireFormat.extractSignal(from: 0x06), .established)
        XCTAssertNil(LXSTWireFormat.extractSignal(from: 0xFF))
        XCTAssertNil(LXSTWireFormat.extractSignal(from: 319)) // 0xFF + 0x40
    }

    func testExtractPreferredProfileFromSignal() {
        // Quality Medium: 0xFF + 0x40 = 319
        let signal: UInt = 319
        let profile = LXSTWireFormat.extractPreferredProfile(from: signal)
        XCTAssertEqual(profile, .qualityMedium)

        // Not a profile signal
        XCTAssertNil(LXSTWireFormat.extractPreferredProfile(from: 0x06))
    }

    // MARK: - Python Wire Compat

    func testPythonPreferredProfileEncoding() throws {
        // Python: signal(Signalling.PREFERRED_PROFILE + self.active_call.profile, link)
        // For QUALITY_MEDIUM (0x40): signal value = 0xFF + 0x40 = 319
        let packed = LXSTWireFormat.packPreferredProfile(.qualityMedium)
        let parsed = try LXSTWireFormat.unpack(packed)

        switch parsed {
        case .signals(let signals):
            XCTAssertEqual(signals.count, 1)
            XCTAssertEqual(signals[0], 319) // 0xFF + 0x40
            // Python receiver: profile = signal - Signalling.PREFERRED_PROFILE
            let profile = signals[0] - UInt(LXSTSignal.preferredProfile)
            XCTAssertEqual(profile, 0x40) // QUALITY_MEDIUM
        default:
            XCTFail("Expected .signals")
        }
    }
}
