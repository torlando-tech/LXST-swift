// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC
//
//
//  AudioTests.swift
//  LXSTSwiftTests
//
//  Tests for Phase 4: Audio Pipeline, Mixer, ToneSource, Resampler, Filters.
//

import XCTest
@testable import LXSTSwift

private func peakMagnitude<S: Sequence>(_ samples: S) -> Int where S.Element == Int16 {
    samples.reduce(0) { current, sample in
        max(current, abs(Int(sample)))
    }
}

final class ResamplerTests: XCTestCase {

    func testIdentityResample() {
        let samples: [Float] = [0.0, 0.5, 1.0, -1.0, -0.5]
        let result = Resampler.resample(samples, fromRate: 48000, toRate: 48000)
        XCTAssertEqual(result, samples)
    }

    func testEmptyResample() {
        let result = Resampler.resample([], fromRate: 48000, toRate: 8000)
        XCTAssertTrue(result.isEmpty)
    }

    func testDownsample6x() {
        // 48kHz -> 8kHz = 6x downsample
        let inputCount = 480
        var input = [Float](repeating: 0, count: inputCount)
        for i in 0..<inputCount {
            input[i] = sin(Float(i) * 2.0 * .pi * 440.0 / 48000.0)
        }
        let output = Resampler.resample(input, fromRate: 48000, toRate: 8000)
        XCTAssertEqual(output.count, 80) // 480 / 6 = 80
    }

    func testUpsample6x() {
        // 8kHz -> 48kHz = 6x upsample
        let inputCount = 80
        var input = [Float](repeating: 0, count: inputCount)
        for i in 0..<inputCount {
            input[i] = sin(Float(i) * 2.0 * .pi * 440.0 / 8000.0)
        }
        let output = Resampler.resample(input, fromRate: 8000, toRate: 48000)
        XCTAssertEqual(output.count, 480)
    }

    func testRoundTripPreservesApproximateShape() {
        // Downsample then upsample should roughly preserve shape
        let inputCount = 480
        var input = [Float](repeating: 0, count: inputCount)
        for i in 0..<inputCount {
            // 200Hz tone, well below Nyquist at 8kHz
            input[i] = sin(Float(i) * 2.0 * .pi * 200.0 / 48000.0)
        }
        let down = Resampler.resample(input, fromRate: 48000, toRate: 8000)
        let up = Resampler.resample(down, fromRate: 8000, toRate: 48000)

        XCTAssertEqual(up.count, inputCount)
        // Check correlation — should be similar
        var sumSqDiff: Float = 0
        for i in 0..<inputCount {
            let diff = input[i] - up[i]
            sumSqDiff += diff * diff
        }
        let rmsDiff = sqrt(sumSqDiff / Float(inputCount))
        XCTAssertLessThan(rmsDiff, 0.15, "Round-trip resampling should be close to original")
    }

    func testInterleavedResample() {
        // 2-channel, 6 frames = 12 samples
        let input: [Float] = [
            0.1, 0.2,  // frame 0: ch0=0.1, ch1=0.2
            0.3, 0.4,  // frame 1
            0.5, 0.6,  // frame 2
            0.7, 0.8,  // frame 3
            0.9, 1.0,  // frame 4
            0.5, 0.3,  // frame 5
        ]
        let output = Resampler.resampleInterleaved(input, channels: 2, fromRate: 48000, toRate: 24000)
        // 6 frames at 48k -> 3 frames at 24k = 6 samples
        XCTAssertEqual(output.count, 6)
    }

    func testInt16Resample() {
        let input: [Int16] = [0, 1000, 2000, 3000, 4000, 5000]
        let output = Resampler.resampleInt16(input, channels: 1, fromRate: 48000, toRate: 24000)
        XCTAssertEqual(output.count, 3)
    }
}

final class SampleConversionTests: XCTestCase {

    func testFloatToInt16() {
        let floats: [Float] = [0.0, 1.0, -1.0, 0.5, -0.5]
        let int16s = floatToInt16(floats)
        XCTAssertEqual(int16s[0], 0)
        XCTAssertEqual(int16s[1], Int16.max)
        XCTAssertEqual(int16s[2], -Int16.max) // -1.0 * 32767 = -32767
        XCTAssertTrue(abs(Int(int16s[3]) - 16383) <= 1)
        XCTAssertTrue(abs(Int(int16s[4]) - (-16383)) <= 1)
    }

    func testInt16ToFloat() {
        let int16s: [Int16] = [0, Int16.max, Int16.min + 1, 16384, -16384]
        let floats = int16ToFloat(int16s)
        XCTAssertEqual(floats[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(floats[1], 1.0, accuracy: 0.001)
        XCTAssertEqual(floats[2], -1.0, accuracy: 0.001)
        XCTAssertEqual(floats[3], 0.5, accuracy: 0.01)
        XCTAssertEqual(floats[4], -0.5, accuracy: 0.01)
    }

    func testRoundTrip() {
        let original: [Float] = [0.0, 0.5, -0.5, 0.99, -0.99]
        let roundTripped = int16ToFloat(floatToInt16(original))
        for i in 0..<original.count {
            XCTAssertEqual(roundTripped[i], original[i], accuracy: 0.001)
        }
    }
}

final class AudioFilterTests: XCTestCase {

    func testHighPassRemovesDC() {
        // A DC signal (all same value) should be attenuated by high-pass
        let dc = [Float](repeating: 0.5, count: 480)
        var hpf = HighPassFilter(cutoffHz: 300)
        // Run a few frames to let filter settle
        _ = hpf.handleFrame(dc, sampleRate: 48000)
        _ = hpf.handleFrame(dc, sampleRate: 48000)
        let output = hpf.handleFrame(dc, sampleRate: 48000)

        // After settling, DC should be nearly zero
        let avgOutput = output.reduce(0, +) / Float(output.count)
        XCTAssertLessThan(abs(avgOutput), 0.05, "High-pass should attenuate DC")
    }

    func testLowPassSmooths() {
        // Alternating samples (Nyquist frequency) should be attenuated by low-pass
        var input = [Float](repeating: 0, count: 480)
        for i in 0..<480 {
            input[i] = (i % 2 == 0) ? 1.0 : -1.0
        }
        var lpf = LowPassFilter(cutoffHz: 1000)
        _ = lpf.handleFrame(input, sampleRate: 48000) // settle
        let output = lpf.handleFrame(input, sampleRate: 48000)

        // High-frequency content should be heavily attenuated
        var maxAmp: Float = 0
        for s in output { maxAmp = max(maxAmp, abs(s)) }
        XCTAssertLessThan(maxAmp, 0.5, "Low-pass should attenuate Nyquist frequency")
    }

    func testBandPassPassesMidFrequency() {
        // Generate a 1kHz tone — should pass through 300-3400Hz band-pass
        var input = [Float](repeating: 0, count: 480)
        for i in 0..<480 {
            input[i] = sin(Float(i) * 2.0 * .pi * 1000.0 / 48000.0)
        }

        var bpf = BandPassFilter(lowCut: 300, highCut: 3400)
        // Let filter settle
        for _ in 0..<5 {
            _ = bpf.handleFrame(input, sampleRate: 48000)
        }
        let output = bpf.handleFrame(input, sampleRate: 48000)

        // Should still have significant energy
        var sumSq: Float = 0
        for s in output { sumSq += s * s }
        let rms = sqrt(sumSq / Float(output.count))
        XCTAssertGreaterThan(rms, 0.1, "Band-pass should pass 1kHz tone")
    }

    func testAGCBoostsQuietSignal() {
        // Quiet signal should be amplified
        var input = [Float](repeating: 0, count: 480)
        for i in 0..<480 {
            input[i] = 0.01 * sin(Float(i) * 2.0 * .pi * 440.0 / 48000.0)
        }

        var agc = AGCFilter(targetLevelDb: -12.0, maxGainDb: 24.0)
        // Run several frames to let AGC converge
        var output = [Float]()
        for _ in 0..<20 {
            output = agc.handleFrame(input, sampleRate: 48000)
        }

        var inputRms: Float = 0
        var outputRms: Float = 0
        for s in input { inputRms += s * s }
        for s in output { outputRms += s * s }
        inputRms = sqrt(inputRms / Float(input.count))
        outputRms = sqrt(outputRms / Float(output.count))

        XCTAssertGreaterThan(outputRms, inputRms, "AGC should amplify quiet signal")
    }

    func testFilterEmptyFrame() {
        var hpf = HighPassFilter(cutoffHz: 300)
        let result = hpf.handleFrame([], sampleRate: 48000)
        XCTAssertTrue(result.isEmpty)
    }
}

final class ToneSourceTests: XCTestCase {

    func testGeneratesSilenceWhenNotStarted() async {
        let tone = ToneSource(frequency: 382, gain: 0.1, ease: false)
        let frame = await tone.generateFrame(samplesPerFrame: 480)
        XCTAssertEqual(frame.count, 480)
        XCTAssertTrue(frame.allSatisfy { $0 == 0.0 })
    }

    func testGeneratesToneWhenStarted() async {
        let tone = ToneSource(frequency: 382, gain: 0.5, ease: false)
        await tone.start()
        let frame = await tone.generateFrame(samplesPerFrame: 480)
        XCTAssertEqual(frame.count, 480)

        // Should have non-zero samples
        let maxAmp = frame.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(maxAmp, 0.1)
    }

    func testStopProducesSilence() async {
        let tone = ToneSource(frequency: 382, gain: 0.5, ease: false)
        await tone.start()
        _ = await tone.generateFrame(samplesPerFrame: 480)
        await tone.stop()
        let frame = await tone.generateFrame(samplesPerFrame: 480)
        XCTAssertTrue(frame.allSatisfy { $0 == 0.0 })
    }

    func testMultiChannel() async {
        let tone = ToneSource(frequency: 440, gain: 0.5, channels: 2, ease: false)
        await tone.start()
        let frame = await tone.generateFrame(samplesPerFrame: 480)
        // 2 channels * 480 samples = 960
        XCTAssertEqual(frame.count, 960)

        // Interleaved: ch0 and ch1 should be same (mono duplicated)
        for i in stride(from: 0, to: 960, by: 2) {
            XCTAssertEqual(frame[i], frame[i + 1], accuracy: 1e-6)
        }
    }

    func testFrequencyContent() async {
        // Generate 1 second of 382Hz tone at 48kHz
        let sampleRate = 48000
        let tone = ToneSource(frequency: 382, gain: 1.0, sampleRate: sampleRate, ease: false)
        await tone.start()

        // Generate a full second
        let frame = await tone.generateFrame(samplesPerFrame: sampleRate)
        XCTAssertEqual(frame.count, sampleRate)

        // Count zero crossings to estimate frequency
        var crossings = 0
        for i in 1..<frame.count {
            if (frame[i - 1] >= 0 && frame[i] < 0) || (frame[i - 1] < 0 && frame[i] >= 0) {
                crossings += 1
            }
        }
        // Each cycle has 2 zero crossings, so freq ≈ crossings / 2
        let estimatedFreq = Float(crossings) / 2.0
        XCTAssertEqual(estimatedFreq, 382.0, accuracy: 5.0)
    }
}

/// Thread-safe box for capturing values in @Sendable closures.
final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: [Float]?

    var value: [Float]? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ v: [Float]) {
        lock.lock()
        _value = v
        lock.unlock()
    }

    func clear() {
        lock.lock()
        _value = nil
        lock.unlock()
    }
}

final class MixerTests: XCTestCase {

    func testSingleSourcePassthrough() async {
        let mixer = Mixer(targetFrameMs: 10, sampleRate: 48000, channels: 1)
        let box = FrameBox()
        await mixer.setSinkCallback { frame in box.set(frame) }

        let input: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        await mixer.handleFrame(input, from: "source1")
        await mixer.mixAndDeliver()

        let received = box.value
        XCTAssertNotNil(received)
        XCTAssertEqual(received?.count, 5)
        for i in 0..<5 {
            XCTAssertEqual(received![i], input[i], accuracy: 1e-6)
        }
    }

    func testTwoSourcesMixed() async {
        let mixer = Mixer()
        let box = FrameBox()
        await mixer.setSinkCallback { frame in box.set(frame) }

        let source1: [Float] = [0.3, 0.3, 0.3]
        let source2: [Float] = [0.2, 0.2, 0.2]
        await mixer.handleFrame(source1, from: "s1")
        await mixer.handleFrame(source2, from: "s2")
        await mixer.mixAndDeliver()

        let received = box.value
        XCTAssertNotNil(received)
        XCTAssertEqual(received?.count, 3)
        for i in 0..<3 {
            XCTAssertEqual(received![i], 0.5, accuracy: 1e-6)
        }
    }

    func testMuteProducesSilence() async {
        let mixer = Mixer()
        let box = FrameBox()
        await mixer.setSinkCallback { frame in box.set(frame) }

        let input: [Float] = [0.5, 0.5, 0.5]
        await mixer.handleFrame(input, from: "s1")
        await mixer.mixAndDeliver()

        // Unmuted: should have non-zero values
        XCTAssertNotNil(box.value)
        XCTAssertGreaterThan(box.value![0], 0.1)

        // Now mute and submit another frame
        await mixer.setMuted(true)
        box.clear()
        await mixer.handleFrame(input, from: "s1")
        await mixer.mixAndDeliver()

        // Muted: gain is 0, so all samples should be 0
        XCTAssertNotNil(box.value)
        XCTAssertTrue(box.value!.allSatisfy { $0 == 0.0 })
    }

    func testClampingAboveOne() async {
        let mixer = Mixer()
        let box = FrameBox()
        await mixer.setSinkCallback { frame in box.set(frame) }

        // Two loud sources that sum > 1.0
        let source1: [Float] = [0.8, 0.8, 0.8]
        let source2: [Float] = [0.8, 0.8, 0.8]
        await mixer.handleFrame(source1, from: "s1")
        await mixer.handleFrame(source2, from: "s2")
        await mixer.mixAndDeliver()

        let received = box.value
        XCTAssertNotNil(received)
        for s in received! {
            XCTAssertLessThanOrEqual(s, 1.0)
            XCTAssertGreaterThanOrEqual(s, -1.0)
        }
    }

    func testNoSourcesNoDelivery() async {
        let mixer = Mixer()
        let box = FrameBox()
        await mixer.setSinkCallback { frame in box.set(frame) }
        await mixer.mixAndDeliver()
        XCTAssertNil(box.value, "Should not deliver when no sources have data")
    }

    func testDropOldFrames() async {
        let mixer = Mixer()
        let box = FrameBox()
        await mixer.setSinkCallback { frame in box.set(frame) }

        // Submit exactly maxFrames + 3 frames
        for i in 0..<(Mixer.maxFrames + 3) {
            let frame: [Float] = [Float(i) * 10.0]
            await mixer.handleFrame(frame, from: "s1")
        }

        // Queue should be capped
        let queueCount = await mixer.queueCount(for: "s1")
        XCTAssertLessThanOrEqual(queueCount, Mixer.maxFrames,
            "Queue should not exceed maxFrames (\(Mixer.maxFrames)), got \(queueCount)")

        // Mix and get the first frame — it should NOT be the oldest (0.0)
        await mixer.mixAndDeliver()
        let received = box.value
        XCTAssertNotNil(received)
        XCTAssertGreaterThan(received![0], 0.0,
            "First delivered frame should not be the oldest submitted frame")
    }
}

final class JitterBufferTests: XCTestCase {

    func testEnqueueDequeue() async {
        let buffer = JitterBuffer(targetDepth: 2, maxDepth: 8)
        let frames: [[Float]] = (0..<5).map { [Float($0)] }
        for frame in frames {
            await buffer.enqueue(frame)
        }
        for i in 0..<5 {
            let frame = await buffer.dequeue()
            XCTAssertEqual(frame, [Float(i)])
        }
    }

    func testPrimingDelaysOutput() async {
        let buffer = JitterBuffer(targetDepth: 3, maxDepth: 8)
        await buffer.enqueue([1.0])
        await buffer.enqueue([2.0])
        // Only 2 frames enqueued, target is 3 — should not release yet
        let result = await buffer.dequeue()
        XCTAssertNil(result)
    }

    func testPrimingReleasesAfterTarget() async {
        let buffer = JitterBuffer(targetDepth: 3, maxDepth: 8)
        await buffer.enqueue([1.0])
        await buffer.enqueue([2.0])
        await buffer.enqueue([3.0])
        // Now primed — dequeue should succeed
        let result = await buffer.dequeue()
        XCTAssertEqual(result, [1.0])
    }

    func testOverflowDropsOldest() async {
        let buffer = JitterBuffer(targetDepth: 1, maxDepth: 3)
        await buffer.enqueue([1.0])
        await buffer.enqueue([2.0])
        await buffer.enqueue([3.0])
        await buffer.enqueue([4.0]) // overflow — drops [1.0]

        let stats = await buffer.stats
        XCTAssertEqual(stats.totalOverflows, 1)
        XCTAssertEqual(stats.depth, 3)

        let first = await buffer.dequeue()
        XCTAssertEqual(first, [2.0])
    }

    func testUnderrunTracking() async {
        let buffer = JitterBuffer(targetDepth: 1, maxDepth: 8)
        await buffer.enqueue([1.0])
        // Primed with 1 frame, dequeue it
        _ = await buffer.dequeue()
        // Now empty — dequeue should be underrun
        let result = await buffer.dequeue()
        XCTAssertNil(result)
        let stats = await buffer.stats
        XCTAssertEqual(stats.totalUnderruns, 1)
    }

    func testResetClearsState() async {
        let buffer = JitterBuffer(targetDepth: 2, maxDepth: 8)
        await buffer.enqueue([1.0])
        await buffer.enqueue([2.0])
        await buffer.enqueue([3.0])
        _ = await buffer.dequeue()

        await buffer.reset()

        let stats = await buffer.stats
        XCTAssertEqual(stats.depth, 0)
        XCTAssertFalse(stats.isPrimed)
        XCTAssertEqual(stats.totalEnqueued, 0)
        XCTAssertEqual(stats.totalDequeued, 0)
        XCTAssertEqual(stats.totalUnderruns, 0)
        XCTAssertEqual(stats.totalOverflows, 0)
    }
}

#if canImport(COpus)
import COpus

final class OpusPLCTests: XCTestCase {

    func testOpusPLCProducesSamples() throws {
        let profile = OpusProfile.voiceMedium
        let codec = try OpusCodec(profile: profile)
        let frameSize = profile.sampleRate * 20 / 1000 // 20ms frame

        // Seed decoder state by decoding a real frame
        var samples = [Int16](repeating: 0, count: frameSize)
        for i in 0..<frameSize {
            samples[i] = Int16(clamping: Int(sin(Double(i) * 2.0 * .pi * 440.0 / Double(profile.sampleRate)) * 16000))
        }
        let encoded = try codec.encode(samples)
        _ = try codec.decode(encoded)

        // Now generate PLC
        let plc = codec.decodePLC(frameSize: frameSize)
        XCTAssertNotNil(plc)
        XCTAssertEqual(plc!.count, frameSize * profile.channels)
    }

    func testOpusPLCOutputNotAllZeros() throws {
        let profile = OpusProfile.voiceMedium
        let codec = try OpusCodec(profile: profile)
        let frameSize = profile.sampleRate * 20 / 1000

        // Seed with a loud tone
        var samples = [Int16](repeating: 0, count: frameSize)
        for i in 0..<frameSize {
            samples[i] = Int16(clamping: Int(sin(Double(i) * 2.0 * .pi * 440.0 / Double(profile.sampleRate)) * 30000))
        }
        let encoded = try codec.encode(samples)
        _ = try codec.decode(encoded)

        let plc = codec.decodePLC(frameSize: frameSize)
        XCTAssertNotNil(plc)
        let hasNonZero = plc!.contains { $0 != 0 }
        XCTAssertTrue(hasNonZero, "PLC output should have non-zero samples (interpolation, not silence)")
    }
}
#endif

final class OpusRoundTripTests: XCTestCase {

    /// Verify voiceMax (48kHz, 2ch) roundtrip produces audible audio
    func testVoiceMaxRoundTrip() throws {
        #if canImport(COpus)
        let profile = OpusProfile.voiceMax  // 48kHz, 2ch, voip
        let codec = try OpusCodec(profile: profile)
        let samplesPerChannel = profile.sampleRate * 60 / 1000 // 60ms = 2880
        let totalSamples = samplesPerChannel * profile.channels // 5760

        // Generate 60ms stereo sine wave at 440Hz
        var pcm = [Int16](repeating: 0, count: totalSamples)
        for i in 0..<samplesPerChannel {
            let sample = Int16(clamping: Int(sin(Double(i) * 2.0 * .pi * 440.0 / Double(profile.sampleRate)) * 10000))
            for c in 0..<profile.channels {
                pcm[i * profile.channels + c] = sample
            }
        }
        let inputPeak = peakMagnitude(pcm)
        print("Input peak: \(inputPeak)")

        // Encode
        let encoded = try codec.encode(pcm)
        print("Encoded: \(encoded.count) bytes")
        print("First 8: \(encoded.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "))")

        // Decode
        let decoded = try codec.decode(encoded)
        let outputPeak = peakMagnitude(decoded)
        print("Decoded: \(decoded.count) samples, peak=\(outputPeak)")

        XCTAssertEqual(decoded.count, totalSamples)
        XCTAssertGreaterThan(outputPeak, 1000, "Decoded audio should be audible, got peak=\(outputPeak)")
        #endif
    }

    /// Test what happens when mono Opus data is decoded with a stereo decoder
    func testMonoDataStereoDecoder() throws {
        #if canImport(COpus)
        // Encode mono
        let monoProfile = OpusProfile.voiceHigh  // 48kHz, 1ch
        let monoCodec = try OpusCodec(profile: monoProfile)
        let spf = monoProfile.sampleRate * 60 / 1000 // 2880

        var monoInput = [Int16](repeating: 0, count: spf)
        for i in 0..<spf {
            monoInput[i] = Int16(clamping: Int(sin(Double(i) * 2.0 * .pi * 440.0 / Double(monoProfile.sampleRate)) * 10000))
        }
        let monoEncoded = try monoCodec.encode(monoInput)
        print("Mono encoded: \(monoEncoded.count) bytes")
        print("Mono first 8: \(monoEncoded.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "))")

        // Decode with stereo decoder
        let stereoProfile = OpusProfile.voiceMax  // 48kHz, 2ch
        let stereoCodec = try OpusCodec(profile: stereoProfile)

        do {
            let decoded = try stereoCodec.decode(monoEncoded)
            let peak = peakMagnitude(decoded)
            print("Stereo decode of mono data: \(decoded.count) samples, peak=\(peak)")
            // If this succeeds, it means Opus CAN decode mono with stereo decoder
            // Check if peak is near-zero (would explain our bug!)
            if peak < 100 {
                print("WARNING: Stereo decoder of mono data produces near-zero peak=\(peak)")
                print("THIS COULD BE THE BUG — Android may be sending mono Opus!")
            }
        } catch {
            print("Stereo decode of mono data FAILED: \(error)")
            // If it fails, channel mismatch causes error, not silence
        }
        #endif
    }
}

final class AudioPipelineTests: XCTestCase {

    func testConfigFromProfile() {
        let profile = TelephonyProfile.qualityMedium
        let config = AudioPipeline.Config(profile: profile)
        XCTAssertEqual(config.codecType, .opus)
        XCTAssertEqual(config.frameTimeMs, 60)
    }

    func testConfigSamplesPerFrame() {
        let config = AudioPipeline.Config(
            codecType: .opus,
            sampleRate: 48000,
            channels: 1,
            frameTimeMs: 20
        )
        XCTAssertEqual(config.samplesPerFrame, 960) // 48000 * 20 / 1000
    }

    func testCodec2ConfigFromProfile() {
        let profile = TelephonyProfile.bandwidthLow
        let config = AudioPipeline.Config(profile: profile)
        XCTAssertEqual(config.codecType, .codec2)
        XCTAssertEqual(config.sampleRate, 8000)
        XCTAssertEqual(config.channels, 1)
        XCTAssertEqual(config.frameTimeMs, 200)
    }

    func testStartStop() async {
        let config = AudioPipeline.Config(
            codecType: .null,
            sampleRate: 48000,
            channels: 1,
            frameTimeMs: 20
        )
        let pipeline = AudioPipeline(config: config)
        await pipeline.start()
        await pipeline.stop()
    }

    func testNullCodecRoundTrip() async {
        let config = AudioPipeline.Config(
            codecType: .null,
            sampleRate: 48000,
            channels: 1,
            frameTimeMs: 10
        )
        let pipeline = AudioPipeline(config: config)
        let codec = NullCodec()

        // Thread-safe boxes for callback results
        final class DataBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _value: Data?
            var value: Data? { lock.lock(); defer { lock.unlock() }; return _value }
            func set(_ v: Data) { lock.lock(); _value = v; lock.unlock() }
        }
        final class FloatBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _value: [Float]?
            var value: [Float]? { lock.lock(); defer { lock.unlock() }; return _value }
            func set(_ v: [Float]) { lock.lock(); _value = v; lock.unlock() }
        }

        let encodedBox = DataBox()
        let decodedBox = FloatBox()

        await pipeline.setEncodedFrameCallback { codecType, data in
            XCTAssertEqual(codecType, .null)
            encodedBox.set(data)
        }

        await pipeline.start()

        // Generate a simple tone frame
        let samplesPerFrame = 480 // 10ms at 48kHz
        var samples = [Float](repeating: 0, count: samplesPerFrame)
        for i in 0..<samplesPerFrame {
            samples[i] = 0.5 * sin(Float(i) * 2.0 * .pi * 440.0 / 48000.0)
        }

        await pipeline.processCapture(samples, codec: codec)
        XCTAssertNotNil(encodedBox.value)

        // Now decode
        await pipeline.setDecodedSamplesCallback { floats, rate, channels in
            decodedBox.set(floats)
            XCTAssertEqual(rate, 48000)
            XCTAssertEqual(channels, 1)
        }

        await pipeline.processReceived(encodedBox.value!, codec: codec)
        XCTAssertNotNil(decodedBox.value)
        XCTAssertEqual(decodedBox.value?.count, samplesPerFrame)
    }
}

// MARK: - Opus Stereo Interop Tests

#if canImport(COpus)
import COpus

final class OpusStereoInteropTests: XCTestCase {

    /// Decode a Hybrid FB stereo 20ms frame containing a 440Hz test tone.
    /// Generated with libopus forced to Hybrid mode (SILK+CELT) at 48kHz/32kbps —
    /// the same encoding Android uses for SHQ profile.
    /// TOC 0x7c = config 15 (Hybrid FB 20ms), stereo, code 0 (single frame).
    func testDecodeHybridFrame20ms() throws {
        let b64 = "fIgDJQllHYiSy+oxGUlp7xO7H28qCQ3yV7leJS7+xqPzXzITPyCEBJPFtP4W73OTG516cfMCuXvgRfrxVEwK"
        let data = Data(base64Encoded: b64)!
        XCTAssertEqual(data[0], 0x7c, "TOC byte should be 0x7c (Hybrid FB stereo code 0)")
        let config = Int(data[0]) >> 3
        XCTAssertEqual(config, 15, "Config should be 15 (Hybrid FB 20ms)")

        var error: Int32 = 0
        guard let decoder = opus_decoder_create(48000, 2, &error) else {
            XCTFail("Failed to create decoder: \(error)")
            return
        }
        defer { opus_decoder_destroy(decoder) }

        var pcm = [Int16](repeating: 0, count: 960 * 2) // 20ms stereo
        let decoded = data.withUnsafeBytes { rawPtr -> Int32 in
            let bytes = rawPtr.bindMemory(to: UInt8.self)
            return opus_decode(decoder, bytes.baseAddress, Int32(data.count),
                             &pcm, 960, 0)
        }

        XCTAssertEqual(decoded, 960, "Should decode 960 samples per channel (20ms)")
        let peak = peakMagnitude(pcm.prefix(Int(decoded) * 2))
        XCTAssertGreaterThan(peak, 1000, "Hybrid 20ms decode peak=\(peak) — should contain audible 440Hz tone")
    }

    /// Decode a Hybrid FB stereo 60ms frame (code 3, 3×20ms) containing a 440Hz test tone.
    /// This matches the exact format Android sends for SHQ calls:
    /// TOC 0x7f = config 15 (Hybrid FB 20ms), stereo, code 3 (VBR, 3 frames).
    func testDecodeHybridFrame60ms() throws {
        let b64 = "f4NIT4gCmqU4WH0AFo0dYtNT0+2qZ7ejPRKQx3CUwTp9q5wCFA1GqaO2UIZ3v10hxkVa9NH3rYZPLd0rPLeUe62O67aHL5Sd1+5wCogCmqU4WH0AFdNVW3gU/qTxqnrHeX80jGtIc8ucoMBBZqXgfzgrqxRKuutQGjWF8bo4kIfIm6iTIDrT9KtE02gUOTsAF7yyhjPNKIUPkPWIApqlOFh7Kc4ZNNmuoFt/pt5nYoS4z1yGDzP82CBA2FFIka19C5qfZ02qOCNloHB5J5lKuVCbzu84HEhinP/OFH/U1uQeAPtLLx1UbzwP"
        let data = Data(base64Encoded: b64)!
        XCTAssertEqual(data[0], 0x7f, "TOC byte should be 0x7f (Hybrid FB stereo code 3)")
        let config = Int(data[0]) >> 3
        XCTAssertEqual(config, 15, "Config should be 15 (Hybrid FB 20ms)")

        var error: Int32 = 0
        guard let decoder = opus_decoder_create(48000, 2, &error) else {
            XCTFail("Failed to create decoder: \(error)")
            return
        }
        defer { opus_decoder_destroy(decoder) }

        var pcm = [Int16](repeating: 0, count: 2880 * 2) // 60ms stereo
        let decoded = data.withUnsafeBytes { rawPtr -> Int32 in
            let bytes = rawPtr.bindMemory(to: UInt8.self)
            return opus_decode(decoder, bytes.baseAddress, Int32(data.count),
                             &pcm, 2880, 0)
        }

        XCTAssertEqual(decoded, 2880, "Should decode 2880 samples per channel (60ms)")
        let peak = peakMagnitude(pcm.prefix(Int(decoded) * 2))
        XCTAssertGreaterThan(peak, 1000, "Hybrid 60ms decode peak=\(peak) — should contain audible 440Hz tone")
    }

    /// Test that our COpus encoder roundtrip works for stereo (baseline).
    func testStereoRoundtrip() throws {
        let codec = try OpusCodec(profile: .voiceMax)
        let spf = 2880 // 60ms at 48kHz, per channel
        let total = spf * 2 // stereo

        // Generate loud 440Hz stereo sine
        var pcm = [Int16](repeating: 0, count: total)
        for i in 0..<spf {
            let sample = Int16(clamping: Int(sin(Double(i) * 2.0 * .pi * 440.0 / 48000.0) * 10000))
            pcm[i * 2] = sample
            pcm[i * 2 + 1] = sample
        }

        let encoded = try codec.encode(pcm)
        let tocByte = encoded[0]
        let config = Int(tocByte) >> 3

        let decoded = try codec.decode(encoded)
        let peak = peakMagnitude(decoded)

        XCTAssertGreaterThan(peak, 1000, "Roundtrip peak=\(peak) TOC=0x\(String(format: "%02x", tocByte)) config=\(config) — should be substantial")
    }

    /// Cross-platform decode test: Homebrew libopus 1.6.1 encoded SILK tone → our COpus 1.5.2 decoder.
    /// This simulates Android NDK libopus → iOS COpus. Uses OpusCodec wrapper (same code path as iOS app).
    func testCrossPlatformSilkDecode() throws {
        // 60ms stereo SILK frame from Homebrew libopus (440Hz tone, 48kHz/32kbps VOIP, forced SILK mode)
        // Frame 9 (after encoder warmup), TOC=0x7f (Hybrid FB stereo code 3)
        let b64 = "f4NESogDJQlje2O9DdiC5xu1+6ONb7+YxSAKZ8JQRUr9ZYkS9JM+Fe1VUxgjEUKeEgOf/ynzhuCa2Q7ALnLWkEQgE/rxVHCaiALCrvMOS/aF4kisywUTKFHHp8EiLkO7Aov6mehHSM02co9k8co3cmSfksfHHDymR+EOuPYVFWOEMLolgdnqHFThOHUfg4BUwAqIAq727K/M/ysWO75jr0wnLcf3TABU0dMw5DP8u2SwqSTUBnWqLrfj56lNAMTLtrPitEnc/qgAKZ3shgJl11FjIcyjpeUtc/o="
        let data = Data(base64Encoded: b64)!
        XCTAssertEqual(data[0], 0x7f, "TOC should be 0x7f (Hybrid/SILK FB stereo code 3)")

        let codec = try OpusCodec(profile: .voiceMax) // 48kHz stereo VOIP 32kbps
        let decoded = try codec.decode(data)
        let peak = peakMagnitude(decoded)

        print("Cross-platform SILK decode: \(data.count)B → \(decoded.count) samples, peak=\(peak)")
        XCTAssertEqual(decoded.count, 2880 * 2, "Should decode 2880 stereo samples (60ms)")
        XCTAssertGreaterThan(peak, 1000, "Cross-platform SILK decode peak=\(peak) — should contain audible 440Hz tone (>1000). If ≤50, SILK decode is broken.")
    }

    /// Cross-platform SHQ decode test: Homebrew libopus 1.6.1 encoded frames → our COpus 1.5.2.
    /// Simulates Android NDK libopus → iOS COpus for the SHQ profile (0x60).
    /// Uses 10 consecutive 60ms stereo 440Hz frames (encoder warmup matters).
    /// Generated by /tmp/encode_shq_tone.c with identical params to Android:
    /// 48kHz, 2ch, VOIP, 32kbps, complexity 10.
    func testDecodeAndroidSHQFrames() throws {
        // 10 consecutive 60ms SHQ frames from Homebrew libopus 1.6.1
        // (same NDK-style prebuilt library Android uses)
        let frames: [String] = [
            // Frame 0: TOC=0xff (CELT FB stereo code 3) — encoder warmup
            "/wN7GT2sVHjt9JSvVIu6Rdr11ijk+buou2zkzC6OQO2ExW2XK/Xvg3W/qdD/0461/fbNFtM4KI2W7iv7kyrInLTjmBgPjgy/OeE/Ays8zwW3sB/JK8GDKGlHgCbESLlYTAkgFidX1rJLJAOApWLILq4Lho9fH/hrpy8tXLvWpvM6wW+k3luZON7vkygeFT6dhhaIE8FJEgqj+YbbfttJ7rAuwwgZi3hA3WSjMH7FIeV1j2QUQT4J7QmeFoTV6cfPsbK72DagQXzg5zUnKE6hfA/k9YfyvGliS7oGSDsyVOc+ttBQg1+j6sAAJSJNpe4=",
            // Frame 1: TOC=0xff
            "/wOsnMpGQdHr9a7A+fuR1HuW7ctlVlTeGTqUvROknmo/yWRmftbOLHGMgYA6EpNtzH2QCwjGcDjVAAtbVKgrr75rLoVuXPOI+da+AG3/8lvurFp4yHwddKwoc1we4PBLUr2v7xL979fM0gMJHo+GosLwACUxsNoYXWC2I8/P14hRyY//RSNcohb80sOdGLjVkONLdGEvXNkLefJJbskT7qytKJG9gCOm34QRpE9gpw9iDoe4NaNZu+bAbEKJI3/m+bwh/DR/eW7BifevIcOtgsdUQotqUSUj1gsvo2YK50cIK8YXbLnIJ0CktgAAJe4=",
            // Frame 2: TOC=0xff
            "/wOsWniCVebWPDH+3XddN9yYYOiBX+bea8kgSdfur7t0ri1RE6eVlSxsPKqj04pnB0/oZfySVoLhU7Qi+lnziGq7IbStP0uGfsR/8gH+21vusDJD++F6zh16V1ZmK+vjzI7YcScSHQMzeiUUQHb3BKJMI3wwHHlWlGpa6FZvbbMClzp2kSi6liS4UGSCmxKnOfW2gkUGCEPmBq3bJ+B/7qycykZB0OUrhqD3otHyq9GuqWt2ttgNgk5CJMZLRz6AFkk8rFfnR58zeMr5PigKWgC/dheGe2/eC1tUqCuvvmsuhW5c84j51r4Abf7W2+4=",
            // Frame 3: TOC=0x9f (SILK FB stereo code 3) — encoder settled
            "nwOsWnjIfB10rCjYuElCxoLh9k5c5bpdq/ueoyRe8PV6dHOETpaPCBClBXo2809tOZ6fxogQYhR5C4eKXBVrElK/ON2/isVMlKWGB8kleBPurK0okb2AI6bSsq8Zbi6buGmi+i2+gIMZnEi01/3EG+hmlB6bABIuNgXApxuG+ShS5iYmfMfPh2AO17W3uHqnCOemh5QTfo0omYKS2AAl7qxaeIJV5tY8JfgE8XLq36tNV1V1KR+8QlubkfmApp5UnITURB9guKIwIps1n2KPVMSyDLWTTgBs9XXJPohWRNQwqjLq2/pemOf/yAf/2+4=",
            // Frame 4: TOC=0x9f
            "nwOwMkP74XrOF3aO1iqYUdEsh7R7Lm0z6ATvjCBirRKAHbvHmZvMD36tk2/4uqJtJtNMbAXBDv5kF7vK0qxt97dRKvxjqO30Pjp4at214H/urJzKRkHQ5V+bvw3klmpOscYcV4CEtxO8rWfWAIMMlcyNPOoFeKOxExyF0vpDeMkrmHT27i6IqwDWTNmVIpscGmhdBo6ujPXGGeAH/tJb7qxaeMh8HXSsKNi4SULGguH2Tlzlul2r+56jJF7w9Xp0c4ROlo8IEKUFejbzT205np/GiBACFHkLh4pcFWsSUr843b+KxUyUpYYHySV6k+4=",
            // Frame 5: TOC=0x9f
            "nwOsrSiRvYAjptKyrxluLpu4aaL6Lb6AgxmcSLTX/cQb6GaUHpsAEi42BcCnG4b5KFLmJiZ8x8+HYA7Xtbe4eqcI56aHlBN+jSiZgpLYACXurFp4glXm1jwl+ATxcurfq01XVXUpH7xCW5uR+YCmnlSchNREH2C4ojAimzWfYo9UxLIMtZNOAGz1dck+iFZE1DCqMurb+l6Y5//IB//b7rAyQ/vhes4Xdo7WKphR0SyHtHsubTPoBO+MIGKtEoAdu8eZm8wPfq2Tb/i6omty9yGIBcEO/mQXu8rSrG33t1Eq/GOo7fQ+Onhq3bXgf+4=",
            // Frame 6: TOC=0x9f
            "nwOsnMpGQdDlX5u/DeSWak6xxhxXgIS3E7ytZ9YAgwyVzI086gV4o7ETHIXS+kN419qYdPbuLoirANZM2ZUimxwaaF0Gjq6M9cYZ4Af+0lvurFp4yHwddKubGb0BQcFteaXsKsKc6Iwwur9Sj34rAFcOa2kAA6wdaVW77UvDns52FVbVOAIUeQuHilwVaxJSvzjcvorF/zSlgAfJJXqT7qytKJG9gCOm0rKvGW4um7hpovotvoCDGZxItNf9xBvoZpQemwASLjYFwKcbhvkoUuYqJnzHz4dgDte1t7h6pwjnpoeUE36NKJmCktgAJe4=",
            // Frame 7: TOC=0x9f
            "nwOsWniCVebWPCX4BPFy6t+rTVdVdSkfvEJbm5H5gKaeVJyE1EQfYLiiMCKbNZ9ij1TEsgy1k04AbPV1yT6IVkTUMKoy6tv6Xpjn/8gH/9vusDJD++F6zhd2jtYqmFHRLIe0ey5tM+gE74wgYq0SgB27x5mbzA9+rZNv+Lqia3L2j+gFwQ7+ZBe7ytKsbfe3USr8Y6jt9D46eGrdteB/7qycykZB0OVfm78N5JZqTrHGHFeAhLcTvK1n1gCDDJXMjTzqBXijsRMchdL6Q3jX2ph09u4uiKsA1kzZlSKbHBpoXQaOroz1xhngB/7SW+4=",
            // Frame 8: TOC=0x9f
            "nwOsWnjIfB10rCjYuElCxoLh9k5c5bpdq/ueoyRe8PV6dHOETpaPCBClBXo2809tOZ6fxogQAhR5C4eKXBVrElK/ON2/isVMlKWGB8klepPurK0okb2AI6bSsq8Zbi6buGmi+i2+gIMZnEi01/3EG+hmlB6bABIuNgXApxuG+ShS5iYmfMfPh2AO17W3uHqnCOemh5QTfo0omYKS2AAl7qxaeIJV5tY8JfgE8XLq36tNV1V1KR+8QlubkfmApp5UnITURB9guKIwIps1n2KPVMSyDLWTTgBs9XXJPohWRNQwqjLq2/pemOf/yAf/2+4=",
            // Frame 9: TOC=0x9f
            "nwOwMkP74XrOF3aO1iqYUdEsh7R7Lm0z6ATvjCBirRKAHbvHmZvMD36tk2/4uqJrcvaP6AXBDv5kF7vK0qxt97dRKvxjqO30Pjp4at214H/urJzKRkHQ5V+bvw3klmpOscYcV4CEtxO8rWfWAIMMlcyNPOoFeKOxExyF0vpDeMkrmHT27i6IqwDWTNmVIpscGmhdBo6ujPXGGeAH/tJb7qxaeMh8HXSsKNi4SULGguH2Tlzlul2r+56jJF7w9Xp0c4ROlo8IEKUFejbzT205nla6M2AKFHkLh4pcFWsSUr843b+KxUyUpYYHySV6k+4=",
        ]

        let codec = try OpusCodec(profile: .voiceMax) // 48kHz, 2ch, VOIP, 32kbps

        for (i, b64) in frames.enumerated() {
            let data = Data(base64Encoded: b64)!
            let toc = data[0]
            let config = Int(toc) >> 3
            let stereo = (Int(toc) >> 2) & 1

            let decoded = try codec.decode(data)
            let peak = peakMagnitude(decoded)

            print("SHQ Frame \(i): \(data.count)B TOC=0x\(String(format: "%02x", toc)) config=\(config) \(stereo == 1 ? "stereo" : "mono") → \(decoded.count) samples, peak=\(peak)")

            XCTAssertEqual(decoded.count, 2880 * 2,
                "Frame \(i) should decode to 5760 stereo samples (60ms)")
            XCTAssertGreaterThan(peak, 1000,
                "Frame \(i) peak=\(peak) — should be >1000 for audible 440Hz. If ≤50, COpus can't decode prebuilt libopus output.")
        }
    }

    /// Test decoding a Hybrid-mode packet generated by forcing encoder to Hybrid.
    /// This isolates whether SILK/Hybrid decode works in our COpus build.
    func testHybridModeDecodeWorks() throws {
        var error: Int32 = 0
        guard let encoder = opus_encoder_create(48000, 2, OPUS_APPLICATION_VOIP, &error) else {
            XCTFail("Encoder create failed: \(error)")
            return
        }
        defer { opus_encoder_destroy(encoder) }

        // Force Hybrid mode explicitly using the private FORCE_MODE CTL.
        // Previous code used bandwidth=1103 (WIDEBAND) instead of 1104 (SUPERWIDEBAND),
        // causing the encoder to produce CELT WB instead of Hybrid.
        // OPUS_MODE_HYBRID = 1001 forces SILK+CELT combination.
        opus_encoder_set_bitrate(encoder, 32000)
        opus_encoder_set_complexity(encoder, 10)
        opus_encoder_set_bandwidth(encoder, 1105) // OPUS_BANDWIDTH_FULLBAND
        opus_encoder_set_force_mode(encoder, OPUS_MODE_HYBRID)

        let spf = 960 // 20ms at 48kHz per channel
        let total = spf * 2
        var pcm = [Int16](repeating: 0, count: total)
        for i in 0..<spf {
            let sample = Int16(clamping: Int(sin(Double(i) * 2.0 * .pi * 440.0 / 48000.0) * 10000))
            pcm[i * 2] = sample
            pcm[i * 2 + 1] = sample
        }

        var outBuf = [UInt8](repeating: 0, count: 4000)
        let encLen = pcm.withUnsafeBufferPointer { pcmPtr in
            opus_encode(encoder, pcmPtr.baseAddress!, Int32(spf), &outBuf, 4000)
        }
        XCTAssertGreaterThan(encLen, 0, "Encode should succeed")

        let tocByte = outBuf[0]
        let config = Int(tocByte) >> 3

        // Now decode
        guard let decoder = opus_decoder_create(48000, 2, &error) else {
            XCTFail("Decoder create failed: \(error)")
            return
        }
        defer { opus_decoder_destroy(decoder) }

        var decodedPcm = [Int16](repeating: 0, count: spf * 2)
        let decodedSamples = opus_decode(decoder, outBuf, encLen, &decodedPcm, Int32(spf), 0)
        XCTAssertEqual(decodedSamples, Int32(spf))

        let peak = peakMagnitude(decodedPcm.prefix(Int(decodedSamples) * 2))
        let isHybrid = config >= 12 && config <= 15
        XCTAssertTrue(isHybrid, "Expected Hybrid mode (config 12-15), got config=\(config) TOC=0x\(String(format: "%02x", tocByte))")
        XCTAssertGreaterThan(peak, 100, "Hybrid decode peak=\(peak) TOC=0x\(String(format: "%02x", tocByte)) config=\(config) — near-zero means SILK/Hybrid broken")
    }
}
#endif
