import Foundation
import Testing
@testable import EuphonaKit

/// A vowel made the source–filter way: a glottal pulse train through second-order resonators.
enum SyntheticVowel {
    static func make(f0: Double, formants: [(hz: Double, bandwidth: Double)], seconds: Double = 0.5) -> [Float] {
        let rate = FormantTracker.sampleRate
        let count = Int(seconds * rate)
        let period = rate / f0
        var signal = [Double](repeating: 0, count: count)
        var next = 0.0
        while Int(next) < count {
            signal[Int(next)] = 1
            next += period
        }
        for (hz, bandwidth) in formants {
            let r = exp(-.pi * bandwidth / rate)
            let a1 = 2 * r * cos(2 * .pi * hz / rate), a2 = -r * r
            var y1 = 0.0, y2 = 0.0
            for i in signal.indices {
                let y = signal[i] + a1 * y1 + a2 * y2
                y2 = y1
                y1 = y
                signal[i] = y
            }
        }
        let peak = signal.map(abs).max() ?? 1
        return signal.map { Float($0 / peak * 0.5) }
    }
}

struct LiveStreamTests {
    static let vowel = [(hz: 700.0, bandwidth: 80.0), (1_220, 90), (2_600, 120)]

    @Test(arguments: [110.0, 220.0])
    func findsTheFormantsOfASyntheticVowel(f0: Double) throws {
        let frames = RealtimeFormantStream().process(SyntheticVowel.make(f0: f0, formants: Self.vowel))
        #expect(frames.count >= 10)
        let f1 = frames.map(\.formants.f1).sorted()[frames.count / 2]
        let f2 = frames.map(\.formants.f2).sorted()[frames.count / 2]
        // A high voice samples the envelope only at its harmonics, so allow it more slack.
        let tolerance = f0 > 200 ? 0.12 : 0.06
        #expect(abs(f1 - 700) / 700 < tolerance)
        #expect(abs(f2 - 1_220) / 1_220 < tolerance)
    }

    @Test func ignoresSilenceAndNoise() {
        let stream = RealtimeFormantStream()
        #expect(stream.process([Float](repeating: 0, count: 16_000)).isEmpty)
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<16_000).map { _ in Float.random(in: -0.2...0.2, using: &generator) }
        #expect(stream.process(noise).isEmpty)
    }

    @Test func liveTimbreSeparatesTheVoices() async throws {
        let analyzer = try EngineTests.analyzer.get()
        func mean(_ name: String) async throws -> Double {
            let stream = RealtimeTimbreStream(analyzer: analyzer)
            let samples = try EuphonaAnalyzer.prepare(try await TestAudio.load(name))
            var scores: [Double] = []
            for start in stride(from: 0, to: samples.count, by: 1_600) {
                if let frame = try stream.process(Array(samples[start..<min(start + 1_600, samples.count)])) {
                    scores.append(frame.score)
                }
            }
            #expect(scores.count >= 4)
            return scores.reduce(0, +) / Double(max(scores.count, 1))
        }
        let feminine = try await mean("feminine"), masculine = try await mean("masculine")
        #expect(feminine > masculine + 20)
    }
}

struct VowelNormsTests {
    @Test func brightnessRunsFromTheMasculineToTheFeminineAverage() {
        for vowel in VowelNorms.vowels {
            let dark = VowelNorms.brightness(vowel.masculine), bright = VowelNorms.brightness(vowel.feminine)
            #expect(dark.vowel.symbol == vowel.symbol && dark.brightness < 1)
            #expect(bright.vowel.symbol == vowel.symbol && bright.brightness > 99)
        }
        let heed = VowelNorms.vowels[0]
        let between = Formants(f1: (heed.masculine.f1 + heed.feminine.f1) / 2, f2: (heed.masculine.f2 + heed.feminine.f2) / 2)
        #expect((35...65).contains(VowelNorms.brightness(between).brightness))
    }
}
