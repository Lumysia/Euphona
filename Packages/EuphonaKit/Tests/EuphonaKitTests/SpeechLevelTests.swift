import Testing
@testable import EuphonaKit

/// Measurement-mode input arrives far quieter than Android's; speech counting must not depend on it.
@Suite(.serialized) struct SpeechLevelTests {
    /// Runs the live counter the way SpeechCapture does: 100 ms chunks, VAD on each due window.
    static func liveSpeech(_ samples: [Float], normalizes: Bool) throws -> (seconds: Double, gain: Float) {
        let analyzer = try EngineTests.analyzer.get()
        var counter = LiveSpeechCounter(normalizesLevel: normalizes)
        var windows: [LiveSpeechCounter.Window] = []
        for start in stride(from: 0, to: samples.count, by: 1600) {
            windows += counter.append(Array(samples[start..<min(start + 1600, samples.count)]))
        }
        if let last = counter.finalWindow() { windows.append(last) }
        for window in windows {
            counter.record(try analyzer.detectSpeech(PCMBuffer(samples: window.samples, sampleRate: 16_000)), in: window)
        }
        return (counter.speechSeconds, counter.levelGain)
    }

    @Test func quietSpeechCountsLikeFullLevelSpeech() async throws {
        let clip = try await TestAudio.load("masculine").samples
        let full = try Self.liveSpeech(clip, normalizes: false).seconds
        // Measurement-mode speech: the loud end around -44 dBFS, whatever the clip's own level.
        let scale = 0.006 / SpeechLevel.loudLevel(clip)
        let quiet = clip.map { $0 * scale }
        let normalized = try Self.liveSpeech(quiet, normalizes: true)
        #expect(normalized.seconds > full * 0.85)
        #expect(normalized.gain > 1)
    }

    @Test(arguments: [0.0005, 0.004] as [Float])
    func roomNoiseIsNotSpeech(amplitude: Float) throws {
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<16_000 * 6).map { _ in Float.random(in: -amplitude...amplitude, using: &generator) }
        #expect(try Self.liveSpeech(noise, normalizes: true).seconds < 0.3)
    }

    @Test func neverAttenuates() {
        var level = SpeechLevel()
        level.observe([Float](repeating: 0.9, count: 1000))
        #expect(level.gain == 1)
        #expect(SpeechLevel.apply(level.gain, to: [0.9]) == [0.9])
    }
}
