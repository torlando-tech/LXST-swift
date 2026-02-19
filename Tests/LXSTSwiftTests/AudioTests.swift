//
//  AudioTests.swift
//  LXSTSwiftTests
//
//  Tests for Phase 4: Audio Pipeline, Mixer, ToneSource, Resampler, Filters.
//

import XCTest
@testable import LXSTSwift

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
