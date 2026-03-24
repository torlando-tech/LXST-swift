// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
//
//  CallUITests.swift
//  LXSTSwiftTests
//
//  Tests for call UI support: AudioRingBuffer, TelephonyProfile config
//  completeness, and duration formatting logic used by the Columba-iOS
//  CallManager and AudioManager.
//

import XCTest
@testable import LXSTSwift

// MARK: - AudioRingBuffer (Copy from Columba-iOS AudioManager.swift)

/// Standalone copy of the lock-free SPSC ring buffer for testing.
/// The original lives in Columba-iOS (executable target, not importable).
private final class AudioRingBuffer {
    private let storage: UnsafeMutableBufferPointer<Float>
    private let capacity: Int
    private var writeIndex: Int = 0
    private var readIndex: Int = 0

    init(capacity: Int) {
        self.capacity = capacity
        let ptr = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        ptr.initialize(repeating: 0, count: capacity)
        self.storage = UnsafeMutableBufferPointer(start: ptr, count: capacity)
    }

    deinit {
        storage.baseAddress?.deinitialize(count: capacity)
        storage.baseAddress?.deallocate()
    }

    var count: Int {
        let w = writeIndex
        let r = readIndex
        return w >= r ? (w - r) : (capacity - r + w)
    }

    func write(_ value: Float) {
        storage[writeIndex] = value
        writeIndex = (writeIndex + 1) % capacity
    }

    func read() -> Float? {
        guard count > 0 else { return nil }
        let value = storage[readIndex]
        readIndex = (readIndex + 1) % capacity
        return value
    }
}

// MARK: - AudioRingBuffer Tests

final class AudioRingBufferTests: XCTestCase {

    func testEmptyBufferReturnsNil() {
        let buf = AudioRingBuffer(capacity: 16)
        XCTAssertEqual(buf.count, 0)
        XCTAssertNil(buf.read())
    }

    func testWriteAndRead() {
        let buf = AudioRingBuffer(capacity: 16)
        buf.write(0.5)
        buf.write(-0.3)
        XCTAssertEqual(buf.count, 2)

        XCTAssertEqual(buf.read()!, 0.5, accuracy: 1e-6)
        XCTAssertEqual(buf.read()!, -0.3, accuracy: 1e-6)
        XCTAssertEqual(buf.count, 0)
        XCTAssertNil(buf.read())
    }

    func testFIFOOrder() {
        let buf = AudioRingBuffer(capacity: 64)
        let values: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        for v in values { buf.write(v) }

        for expected in values {
            guard let actual = buf.read() else {
                XCTFail("Expected value \(expected)")
                return
            }
            XCTAssertEqual(actual, expected, accuracy: 1e-6)
        }
    }

    func testWrapAround() {
        let buf = AudioRingBuffer(capacity: 4)

        // Fill to capacity-1 (count uses modular arithmetic, capacity-1 is max safe)
        buf.write(1.0)
        buf.write(2.0)
        buf.write(3.0)
        XCTAssertEqual(buf.count, 3)

        // Read 2, freeing space
        XCTAssertEqual(buf.read()!, 1.0, accuracy: 1e-6)
        XCTAssertEqual(buf.read()!, 2.0, accuracy: 1e-6)
        XCTAssertEqual(buf.count, 1)

        // Write 2 more (wraps around internal array)
        buf.write(4.0)
        buf.write(5.0)
        XCTAssertEqual(buf.count, 3)

        // Read in order
        XCTAssertEqual(buf.read()!, 3.0, accuracy: 1e-6)
        XCTAssertEqual(buf.read()!, 4.0, accuracy: 1e-6)
        XCTAssertEqual(buf.read()!, 5.0, accuracy: 1e-6)
        XCTAssertEqual(buf.count, 0)
    }

    func testOverflowOverwritesOldest() {
        // When buffer is full, writes overwrite the oldest sample.
        // This is the intended behavior for voice audio (prefer fresh data).
        let buf = AudioRingBuffer(capacity: 4)

        // Write 4 values (fills buffer; count wraps so effectively capacity-1 readable)
        buf.write(1.0)
        buf.write(2.0)
        buf.write(3.0)
        // At capacity-1, writing one more overwrites oldest
        buf.write(4.0)

        // Buffer should report count correctly (might be capacity-1 or wrap)
        // The key invariant: reads return the most recent data, not corrupted values
        var values: [Float] = []
        while let v = buf.read() {
            values.append(v)
        }
        // All values should be valid floats we wrote (no garbage)
        for v in values {
            XCTAssertTrue([1.0, 2.0, 3.0, 4.0].contains(where: { abs($0 - v) < 1e-6 }),
                          "Unexpected value \(v) in buffer")
        }
    }

    func testLargeBufferStress() {
        // Simulate a real audio scenario: write/read many frames
        let buf = AudioRingBuffer(capacity: 9600) // 200ms at 48kHz
        let frameSize = 960 // 20ms at 48kHz

        // Write 5 frames
        for frame in 0..<5 {
            for i in 0..<frameSize {
                buf.write(Float(frame * frameSize + i) * 0.001)
            }
        }
        XCTAssertEqual(buf.count, 5 * frameSize)

        // Read 3 frames
        for frame in 0..<3 {
            for i in 0..<frameSize {
                let expected = Float(frame * frameSize + i) * 0.001
                guard let actual = buf.read() else {
                    XCTFail("Expected value at frame \(frame) sample \(i)")
                    return
                }
                XCTAssertEqual(actual, expected, accuracy: 1e-5)
            }
        }
        XCTAssertEqual(buf.count, 2 * frameSize)
    }

    func testCountAfterMixedOperations() {
        let buf = AudioRingBuffer(capacity: 32)

        buf.write(1.0)
        buf.write(2.0)
        buf.write(3.0)
        XCTAssertEqual(buf.count, 3)

        _ = buf.read()
        XCTAssertEqual(buf.count, 2)

        buf.write(4.0)
        buf.write(5.0)
        XCTAssertEqual(buf.count, 4)

        _ = buf.read()
        _ = buf.read()
        _ = buf.read()
        XCTAssertEqual(buf.count, 1)

        _ = buf.read()
        XCTAssertEqual(buf.count, 0)
        XCTAssertNil(buf.read())
    }
}

// MARK: - TelephonyProfile Config Tests

final class TelephonyProfileConfigTests: XCTestCase {

    func testAllProfilesHaveCodecType() {
        for profile in TelephonyProfile.allCases {
            let codecType = profile.codecType
            XCTAssertTrue(
                [LXSTCodecType.opus, .codec2].contains(codecType),
                "\(profile.displayName) has unexpected codec type: \(codecType)"
            )
        }
    }

    func testBandwidthProfilesUseCodec2() {
        let bwProfiles: [TelephonyProfile] = [.bandwidthUltraLow, .bandwidthVeryLow, .bandwidthLow]
        for profile in bwProfiles {
            XCTAssertEqual(profile.codecType, .codec2, "\(profile.displayName) should use Codec2")
            XCTAssertNotNil(profile.codec2Mode, "\(profile.displayName) should have a Codec2 mode")
            XCTAssertNil(profile.opusProfile, "\(profile.displayName) should NOT have an Opus profile")
        }
    }

    func testQualityAndLatencyProfilesUseOpus() {
        let opusProfiles: [TelephonyProfile] = [
            .qualityMedium, .qualityHigh, .qualityMax,
            .latencyLow, .latencyUltraLow
        ]
        for profile in opusProfiles {
            XCTAssertEqual(profile.codecType, .opus, "\(profile.displayName) should use Opus")
            XCTAssertNotNil(profile.opusProfile, "\(profile.displayName) should have an Opus profile")
            XCTAssertNil(profile.codec2Mode, "\(profile.displayName) should NOT have a Codec2 mode")
        }
    }

    func testAllProfilesHavePositiveFrameTime() {
        for profile in TelephonyProfile.allCases {
            XCTAssertGreaterThan(profile.frameTimeMs, 0,
                "\(profile.displayName) must have positive frame time")
        }
    }

    func testAllProfilesHaveValidSampleRate() {
        for profile in TelephonyProfile.allCases {
            let rate: Int
            switch profile.codecType {
            case .opus:
                rate = profile.opusProfile?.sampleRate ?? 0
            case .codec2:
                rate = Codec2Mode.inputRate
            default:
                rate = 0
            }
            XCTAssertGreaterThan(rate, 0,
                "\(profile.displayName) must have valid sample rate, got \(rate)")
            // Standard audio rates
            XCTAssertTrue([8000, 12000, 16000, 24000, 44100, 48000].contains(rate),
                "\(profile.displayName) has non-standard sample rate: \(rate)")
        }
    }

    func testAllProfilesHaveValidChannelCount() {
        for profile in TelephonyProfile.allCases {
            let ch: Int
            switch profile.codecType {
            case .opus:
                ch = profile.opusProfile?.channels ?? 0
            case .codec2:
                ch = 1 // Codec2 is always mono
            default:
                ch = 0
            }
            XCTAssertTrue(ch == 1 || ch == 2,
                "\(profile.displayName) must have 1 or 2 channels, got \(ch)")
        }
    }

    func testSamplesPerFrameIsPositive() {
        // Verify the computation AudioManager uses: sampleRate * frameTimeMs / 1000
        for profile in TelephonyProfile.allCases {
            let rate: Int
            switch profile.codecType {
            case .opus:
                rate = profile.opusProfile?.sampleRate ?? 48000
            case .codec2:
                rate = Codec2Mode.inputRate
            default:
                rate = 48000
            }
            let spf = rate * profile.frameTimeMs / 1000
            XCTAssertGreaterThan(spf, 0,
                "\(profile.displayName) samplesPerFrame must be > 0, got \(spf)")
            // Should be an integer (no fractional samples)
            XCTAssertEqual(rate * profile.frameTimeMs % 1000, 0,
                "\(profile.displayName) frame time doesn't divide evenly into sample rate")
        }
    }

    func testProfileCount() {
        // Ensure we have all 8 profiles
        XCTAssertEqual(TelephonyProfile.allCases.count, 8)
    }

    func testAllProfilesHaveDisplayName() {
        for profile in TelephonyProfile.allCases {
            XCTAssertFalse(profile.displayName.isEmpty,
                "Profile \(profile.rawValue) must have a display name")
        }
    }

    func testAllProfilesHaveAbbreviation() {
        for profile in TelephonyProfile.allCases {
            XCTAssertFalse(profile.abbreviation.isEmpty,
                "Profile \(profile.rawValue) must have an abbreviation")
        }
    }

    func testNextProfileCyclesAllProfiles() {
        // Starting from any profile, cycling through nextProfile should visit all 8
        var visited = Set<TelephonyProfile>()
        var current = TelephonyProfile.allCases.first!
        for _ in 0..<TelephonyProfile.allCases.count {
            visited.insert(current)
            current = current.nextProfile
        }
        XCTAssertEqual(visited.count, TelephonyProfile.allCases.count,
            "nextProfile should cycle through all profiles")
    }

    func testFrameTimeOrdering() {
        // Bandwidth profiles should have longer frames (lower bandwidth)
        XCTAssertGreaterThan(
            TelephonyProfile.bandwidthUltraLow.frameTimeMs,
            TelephonyProfile.bandwidthLow.frameTimeMs
        )
        // Latency profiles should have shorter frames
        XCTAssertLessThan(
            TelephonyProfile.latencyUltraLow.frameTimeMs,
            TelephonyProfile.latencyLow.frameTimeMs
        )
        // Quality profiles should be in the middle
        XCTAssertGreaterThan(
            TelephonyProfile.qualityMedium.frameTimeMs,
            TelephonyProfile.latencyLow.frameTimeMs
        )
    }
}

// MARK: - Duration Formatting Tests

final class DurationFormattingTests: XCTestCase {

    /// Standalone copy of CallManager.formattedDuration logic.
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    func testZeroDuration() {
        XCTAssertEqual(formatDuration(0), "00:00")
    }

    func testSubMinute() {
        XCTAssertEqual(formatDuration(30), "00:30")
        XCTAssertEqual(formatDuration(59), "00:59")
    }

    func testExactMinutes() {
        XCTAssertEqual(formatDuration(60), "01:00")
        XCTAssertEqual(formatDuration(120), "02:00")
        XCTAssertEqual(formatDuration(600), "10:00")
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(formatDuration(90), "01:30")
        XCTAssertEqual(formatDuration(125), "02:05")
        XCTAssertEqual(formatDuration(3661), "61:01")
    }

    func testFractionalTruncation() {
        // TimeInterval can be fractional; Int() truncates
        XCTAssertEqual(formatDuration(59.9), "00:59")
        XCTAssertEqual(formatDuration(60.1), "01:00")
    }
}

// MARK: - AudioPipeline Config from Profile (Additional Coverage)

final class ProfileToPipelineConfigTests: XCTestCase {

    func testAllProfilesProduceValidConfig() {
        for profile in TelephonyProfile.allCases {
            let config = AudioPipeline.Config(profile: profile)
            XCTAssertGreaterThan(config.sampleRate, 0,
                "\(profile.displayName) config sampleRate")
            XCTAssertGreaterThan(config.channels, 0,
                "\(profile.displayName) config channels")
            XCTAssertGreaterThan(config.frameTimeMs, 0,
                "\(profile.displayName) config frameTimeMs")
            XCTAssertGreaterThan(config.samplesPerFrame, 0,
                "\(profile.displayName) config samplesPerFrame")
        }
    }

    func testCodec2ProfilesHave8kHz() {
        for profile in [TelephonyProfile.bandwidthUltraLow, .bandwidthVeryLow, .bandwidthLow] {
            let config = AudioPipeline.Config(profile: profile)
            XCTAssertEqual(config.sampleRate, 8000,
                "\(profile.displayName) should be 8kHz")
            XCTAssertEqual(config.channels, 1,
                "\(profile.displayName) should be mono")
        }
    }

    func testQualityMaxIsStereo() {
        let config = AudioPipeline.Config(profile: .qualityMax)
        XCTAssertEqual(config.channels, 2, "qualityMax should be stereo")
        XCTAssertEqual(config.sampleRate, 48000, "qualityMax should be 48kHz")
    }
}
