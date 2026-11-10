import Foundation
import Synchronization
import Testing
@testable import EuphonaKit

/// Two FLEURS Mandarin dev clips (CC BY 4.0), see Fixtures/README.md.
enum TestAudio {
    static let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")

    static func load(_ name: String) async throws -> PCMBuffer {
        try await AudioFileReader.read(directory.appending(path: "\(name).wav"))
    }
}

@Suite(.serialized) struct EngineTests {
    static let analyzer = Result { try EuphonaAnalyzer() }

    @Test func timbreSeparatesTheVoices() async throws {
        let analyzer = try Self.analyzer.get()
        let feminine = try analyzer.analyze(try await TestAudio.load("feminine"), profile: .feminization)
        let masculine = try analyzer.analyze(try await TestAudio.load("masculine"), profile: .feminization)
        #expect(feminine.timbre.score > 60)
        #expect(masculine.timbre.score < 40)
        for result in [feminine, masculine] {
            // Healthy, fluent read speech (FLEURS): neither flow nor ease may cost it anything.
            #expect(result.flow.score > Scoring.fluentLevel && result.ease > Scoring.fluentLevel)
            #expect(result.flow.articulationRate > 0 && (0..<1).contains(result.flow.pauseShare))
            #expect(!result.timbre.windows.isEmpty)
            #expect(result.modelVersion == EuphonaAnalyzer.modelVersion)
            #expect(try EuphonaResult(json: result.encodedJSON()) == result)
        }
        let high = try #require(feminine.f0.speakingHz), low = try #require(masculine.f0.speakingHz)
        #expect(high > low + 40)
    }

    @Test func reportsMonotonicProgress() async throws {
        let fractions = Mutex<[Double]>([])
        _ = try Self.analyzer.get().analyze(try await TestAudio.load("feminine"), profile: .feminization) { progress in
            fractions.withLock { $0.append(progress.overallFraction) }
        }
        let values = fractions.withLock { $0 }
        #expect(values.count > 3)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })
    }

    @Test func detectsSpeechInsideTheClip() async throws {
        let audio = try await TestAudio.load("masculine")
        let segments = try Self.analyzer.get().detectSpeech(audio)
        #expect(!segments.isEmpty)
        #expect(segments.allSatisfy { $0.start >= 0 && $0.end <= audio.duration + 0.01 && $0.duration > 0 })
    }

    @Test func silenceHasNoSpeech() throws {
        let silence = PCMBuffer(samples: [Float](repeating: 0, count: 16_000 * 6), sampleRate: 16_000)
        #expect(throws: AnalysisError.noSpeech) { try Self.analyzer.get().analyze(silence, profile: .feminization) }
        #expect(throws: AnalysisError.noSpeech) { try Self.analyzer.get().voiceQuality(silence) }
    }

    @Test func otherSampleRatesGiveTheSameScores() async throws {
        let analyzer = try Self.analyzer.get()
        let audio = try await TestAudio.load("feminine")
        let stereo44 = PCMBuffer(samples: try EuphonaAnalyzer.resample(audio.samples, from: 16_000, to: 44_100).flatMap { [$0, $0] },
                                 sampleRate: 44_100, channels: 2)
        let a = try analyzer.analyze(audio, profile: .feminization).timbre.score
        let b = try analyzer.analyze(stereo44, profile: .feminization).timbre.score
        #expect(abs(a - b) < 3)
    }

    @Test func voiceQualityMeasuresSpeechAndChecksTheRecording() async throws {
        let result = try Self.analyzer.get().voiceQuality(try await TestAudio.load("feminine"))
        #expect((0...100).contains(result.score))
        // A clean studio clip: no clipping, little noise, but far shorter than the 20 s needed.
        #expect(result.check.issues == [.tooLittleVoice])
        #expect(result.features.f0Median > 150)
        #expect(result.features.hnrDb > 5)
        #expect(result.features.jitterLocal > 0 && result.features.jitterLocal < 0.05)
    }

    @Test func realtimeF0AgreesWithOfflineAnalysis() async throws {
        let analyzer = try Self.analyzer.get()
        let speech = try await TestAudio.load("masculine")
        let offline = try #require(try analyzer.analyze(speech, profile: .feminization).f0.speakingHz)
        let stream = RealtimeF0Stream(analyzer: analyzer, outputRateHz: 30)
        var frames: [F0Frame] = []
        for start in stride(from: 0, to: speech.samples.count, by: 512) {
            frames += try stream.process(Array(speech.samples[start..<min(start + 512, speech.samples.count)]))
        }
        #expect(abs(Double(frames.count) - speech.duration * 30) < 30)
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.timestamp < $1.timestamp })
        let voiced = frames.filter(\.voiced).map { Double($0.f0Hz) }
        #expect(voiced.count > 50)
        #expect(abs(try #require(EuphonaResult.F0Metrics.median(voiced)) - offline) < 10)
    }

    @Test func spectrumPeaksAtTheTone() {
        let spectrum = SpectrumStream()
        let tone = (0..<16_000).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / 16_000)) }
        let frames = spectrum.process(tone)
        let last = frames.last!
        let peak = last.magnitudes.indices.max { last.magnitudes[$0] < last.magnitudes[$1] }!
        #expect(abs(Float(peak + last.firstBinIndex) * last.binHz - 440) < 5)
        // A half-scale sine reads about -6 dBFS.
        #expect(abs(last.magnitudes[peak] + 6) < 1.5)
    }
}

/// The overall score: even, continuous, gentle with faults, symmetric between goals.
struct ScoringTests {
    /// `fluency` as flow, with full ease.
    func final(_ timbre: Double, _ fluency: Double, _ f0: Double?, _ goal: ScoreProfile = .feminization) -> Double {
        EuphonaAnalyzer.score(profile: goal, timbreScore: timbre, flow: fluency, ease: 100, f0Hz: f0).finalScore
    }

    @Test func hasNoCliffs() {
        // One step in any component moves the score by at most about a point.
        for step in 0..<100 {
            let x = Double(step)
            #expect(abs(final(x + 1, 70, 190) - final(x, 70, 190)) <= 0.61)
            #expect(abs(final(85, x + 1, 190) - final(85, x, 190)) <= 0.7)
            #expect(abs(final(85, 70, 100 + 2 * x + 2) - final(85, 70, 100 + 2 * x)) <= 1.4)
        }
    }

    @Test func faultsCostAtMostAFifth() {
        let fluent = EuphonaAnalyzer.score(profile: .feminization, timbreScore: 80, flow: 95, ease: 90, f0Hz: 200)
        let strained = EuphonaAnalyzer.score(profile: .feminization, timbreScore: 80, flow: 100, ease: 0, f0Hz: 200)
        #expect(fluent.finalScore == fluent.voice)
        #expect(abs(strained.finalScore - 0.8 * strained.voice) < 1e-9)
    }

    @Test func theLowerOfFlowAndEaseSetsTheFluency() {
        let halting = EuphonaAnalyzer.score(profile: .feminization, timbreScore: 80, flow: 40, ease: 95, f0Hz: 200)
        let pressed = EuphonaAnalyzer.score(profile: .feminization, timbreScore: 80, flow: 95, ease: 40, f0Hz: 200)
        #expect(halting.finalScore == pressed.finalScore && halting.finalScore < halting.voice)
        #expect(halting.fluencyMetric == .flow && pressed.fluencyMetric == .ease)
    }

    @Test func flowCostsOnlyRushedOrHaltingSpeech() {
        #expect(SpeechFlow.score(rate: 4, pauseShare: 0.1) == 100)
        // A slow style is not a fault.
        #expect(SpeechFlow.score(rate: 1, pauseShare: 0.1) == 100)
        #expect(SpeechFlow.score(rate: 7, pauseShare: 0.1) == 0 && SpeechFlow.score(rate: 4, pauseShare: 0.55) == 0)
        let between = SpeechFlow.score(rate: 6, pauseShare: 0.1)
        #expect(between > 0 && between < 100)
    }

    @Test func fullMarksNeedTimbreAndPitchAtTheGoal() {
        #expect(final(100, 90, 220) == 100)
        #expect(final(90, 90, 220) < 95)
        #expect(final(100, 90, 160) < 90)
    }

    @Test func raisedPitchWithoutResonanceIsNotPunishedTwice() {
        // Pitch at the goal, timbre far from it: the timbre share is simply missing.
        #expect(abs(final(20, 90, 250) - (0.6 * 20 + 0.4 * 100)) < 1e-9)
    }

    @Test func pitchMovesEvenlyInSemitones() {
        #expect(Scoring.pitchProgress(Scoring.masculinePitchHz, goal: .feminization) == 0)
        #expect(abs(Scoring.pitchProgress(Scoring.femininePitchHz, goal: .feminization) - 100) < 1e-9)
        #expect(abs(Scoring.pitchProgress(Scoring.pitchMidpointHz, goal: .feminization) - 50) < 1e-9)
    }

    @Test func goalsAreMirrorImages() {
        let feminine = final(70, 80, 190, .feminization)
        let mirrored = Scoring.masculinePitchHz * Scoring.femininePitchHz / 190
        #expect(abs(final(30, 80, mirrored, .masculinization) - feminine) < 1e-9)
    }

    @Test func withoutPitchTimbreCarriesTheVoice() {
        #expect(final(70, 90, nil) == 70)
    }

    @Test func theBottleneckIsTheBiggestLoss() {
        #expect(EuphonaAnalyzer.score(profile: .feminization, timbreScore: 30, flow: 90, ease: 95, f0Hz: 210).bottleneck == .timbre)
        #expect(EuphonaAnalyzer.score(profile: .feminization, timbreScore: 95, flow: 90, ease: 95, f0Hz: 130).bottleneck == .f0)
        #expect(EuphonaAnalyzer.score(profile: .feminization, timbreScore: 95, flow: 20, ease: 95, f0Hz: 210).bottleneck == .flow)
        #expect(EuphonaAnalyzer.score(profile: .feminization, timbreScore: 99, flow: 95, ease: 95, f0Hz: 220).bottleneck == nil)
    }
}
