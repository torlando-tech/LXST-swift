// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
//
//  CodecTests.swift
//  LXSTSwiftTests
//
//  Tests for codec wrappers (OpusCodec, Codec2Codec).
//  When C libraries are not linked, stubs throw appropriately.
//

import XCTest
@testable import LXSTSwift

final class CodecTests: XCTestCase {

    // MARK: - Codec2 Mode to C Constant Mapping

    func testCodec2ModeConstants() {
        // Verify our Codec2Mode enum rawValues match Python MODE_HEADERS
        XCTAssertEqual(Codec2Mode.codec2_700C.rawValue, 0x00)
        XCTAssertEqual(Codec2Mode.codec2_1200.rawValue, 0x01)
        XCTAssertEqual(Codec2Mode.codec2_1300.rawValue, 0x02)
        XCTAssertEqual(Codec2Mode.codec2_1400.rawValue, 0x03)
        XCTAssertEqual(Codec2Mode.codec2_1600.rawValue, 0x04)
        XCTAssertEqual(Codec2Mode.codec2_2400.rawValue, 0x05)
        XCTAssertEqual(Codec2Mode.codec2_3200.rawValue, 0x06)
    }

    // MARK: - Opus Codec Type Check

    func testOpusCodecTypeIsOpus() {
        // When COpus is not linked, init should throw
        // When COpus IS linked, codecType should be .opus
        do {
            let codec = try OpusCodec(profile: .voiceMedium)
            XCTAssertEqual(codec.codecType, .opus)
            XCTAssertEqual(codec.channels, 1)
            XCTAssertEqual(codec.inputRate, 24000)
            XCTAssertEqual(codec.outputRate, 24000)
        } catch {
            // Expected when COpus is not linked
            XCTAssertTrue("\(error)".contains("not available") || "\(error)".contains("Opus"))
        }
    }

    func testOpusCodecAllProfiles() {
        for profile in OpusProfile.allCases {
            do {
                let codec = try OpusCodec(profile: profile)
                XCTAssertEqual(codec.codecType, .opus)
                XCTAssertEqual(codec.channels, profile.channels)
                XCTAssertEqual(codec.inputRate, profile.sampleRate)
            } catch {
                // Expected when COpus is not linked
                XCTAssertTrue("\(error)".contains("not available") || "\(error)".contains("Opus"))
            }
        }
    }

    // MARK: - Codec2 Type Check

    func testCodec2CodecTypeIsCodec2() {
        do {
            let codec = try Codec2Codec(mode: .codec2_2400)
            XCTAssertEqual(codec.codecType, .codec2)
            XCTAssertEqual(codec.channels, 1)
            XCTAssertEqual(codec.inputRate, 8000)
            XCTAssertEqual(codec.outputRate, 8000)
        } catch {
            // Expected when CCodec2 is not linked
            XCTAssertTrue("\(error)".contains("not available") || "\(error)".contains("Codec2"))
        }
    }

    func testCodec2AllModes() {
        for mode in Codec2Mode.allCases {
            do {
                let codec = try Codec2Codec(mode: mode)
                XCTAssertEqual(codec.codecType, .codec2)
            } catch {
                // Expected when CCodec2 is not linked
                XCTAssertTrue("\(error)".contains("not available") || "\(error)".contains("Codec2"))
            }
        }
    }

    // MARK: - Opus Encode/Decode (when available)

    #if canImport(COpus)
    func testOpusRoundTrip() throws {
        let codec = try OpusCodec(profile: .voiceMedium)

        // 60ms at 24kHz mono = 1440 samples
        let frameSize = 1440
        var samples = [Int16](repeating: 0, count: frameSize)
        // Generate a simple sine wave
        for i in 0..<frameSize {
            samples[i] = Int16(sin(Double(i) * 2.0 * .pi * 440.0 / 24000.0) * 16000)
        }

        let encoded = try codec.encode(samples)
        XCTAssertTrue(encoded.count > 0, "Encoded data should not be empty")
        XCTAssertTrue(encoded.count < samples.count * 2, "Encoded should be smaller than raw")

        let decoded = try codec.decode(encoded)
        XCTAssertEqual(decoded.count, frameSize, "Decoded samples should match frame size")
    }
    #endif

    // MARK: - Codec2 Encode/Decode (when available)

    #if canImport(CCodec2)
    func testCodec2RoundTrip() throws {
        let codec = try Codec2Codec(mode: .codec2_2400)

        // codec2_2400 SPF is 160 (20ms at 8kHz)
        let samplesPerFrame = 160
        var samples = [Int16](repeating: 0, count: samplesPerFrame)
        for i in 0..<samplesPerFrame {
            samples[i] = Int16(sin(Double(i) * 2.0 * .pi * 440.0 / 8000.0) * 16000)
        }

        let encoded = try codec.encode(samples)
        XCTAssertTrue(encoded.count > 1, "Encoded should have mode header + data")
        XCTAssertEqual(encoded[0], Codec2Mode.codec2_2400.rawValue, "First byte should be mode header")

        let decoded = try codec.decode(encoded)
        XCTAssertEqual(decoded.count, samplesPerFrame, "Decoded samples should match frame size")
    }
    #endif

    // MARK: - Wire Format Integration

    func testCodecTypeFromProfile() {
        XCTAssertEqual(TelephonyProfile.bandwidthUltraLow.codecType, .codec2)
        XCTAssertEqual(TelephonyProfile.bandwidthVeryLow.codecType, .codec2)
        XCTAssertEqual(TelephonyProfile.bandwidthLow.codecType, .codec2)
        XCTAssertEqual(TelephonyProfile.qualityMedium.codecType, .opus)
        XCTAssertEqual(TelephonyProfile.qualityHigh.codecType, .opus)
        XCTAssertEqual(TelephonyProfile.qualityMax.codecType, .opus)
        XCTAssertEqual(TelephonyProfile.latencyLow.codecType, .opus)
        XCTAssertEqual(TelephonyProfile.latencyUltraLow.codecType, .opus)
    }
}
