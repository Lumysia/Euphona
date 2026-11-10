import AVFoundation
import Foundation

/// Euphona's analysis engine: speech detection, pitch, timbre, flow, ease, the overall score and
/// voice quality, all on the device. Calls may come from any thread; the models serialize their runs.
public final class EuphonaAnalyzer: Sendable {
    /// Identifies the models behind a result; stored in every result as `modelVersion`.
    public static let modelVersion = "euphona-2026.11.3"
    static let sampleRate = SpeechDetector.sampleRate

    public let settings: AnalyzerSettings
    let speech: SpeechDetector
    let pitch: PitchTracker
    let encoder: SpeakerEncoder
    let heads: ScoreHeads
    private let quality: ONNXModel

    public init(settings: AnalyzerSettings = .standard) throws {
        let threads = max(1, settings.threads)
        speech = SpeechDetector(model: try ONNXModel(named: "EuphonaVAD", threads: 1))
        pitch = PitchTracker(model: try ONNXModel(named: "EuphonaF0", threads: threads))
        encoder = SpeakerEncoder(model: try ONNXModel(named: "EuphonaECAPA", threads: threads))
        heads = ScoreHeads(timbre: try ONNXModel(named: "EuphonaTimbre", threads: 1),
                           ease: try ONNXModel(named: "EuphonaEase", threads: 1))
        quality = try ONNXModel(named: "EuphonaVoiceQuality", threads: 1)
        self.settings = settings
    }

    // MARK: Voice analysis

    public func analyze(
        _ audio: PCMBuffer,
        profile: ScoreProfile,
        progress: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) throws -> EuphonaResult {
        let report = { (stage: AnalysisStage, fraction: Double) in
            progress?(AnalysisProgress(kind: .voiceAnalysis, stage: stage, stageFraction: fraction))
        }
        let samples = try Self.prepare(audio)
        report(.detectingSpeech, 0)
        let segments = try speech.segments(samples)
        guard !segments.isEmpty else { throw AnalysisError.noSpeech }
        report(.analyzingPitch, 0)
        let track = try pitch.track(samples)
        let windows = EmbeddingWindows(segments: segments)
        report(.extractingFeatures, 0)
        let embeddings = try encoder.embed(samples, windows) { done, total in
            report(.extractingFeatures, Double(done) / Double(max(total, 1)))
        }

        report(.scoringTimbre, 0)
        let timbre = try heads.timbre(embeddings).map { Double($0) * 100 }
        let timbreScore = timbre.reduce(0, +) / Double(timbre.count)

        report(.scoringFlow, 0)
        let flow = SpeechFlow.measure(samples: samples, segments: segments)
        let stats = EmbeddingMath.statistics(embeddings)
        let ease = Double(try heads.ease(stats.mean + stats.std))

        report(.calculatingScores, 0)
        let f0 = f0Metrics(track, segments: segments)
        let quality = VoiceQuality(samples: samples, segments: segments, pitch: track)
        report(.completed, 1)

        let seconds = { (sample: Int) in Double(sample) / Double(Self.sampleRate) }
        var speechOffset = 0.0
        let speechSegments = segments.map { range -> EuphonaResult.SpeechSegment in
            let length = seconds(range.count)
            defer { speechOffset += length }
            return .init(startSeconds: seconds(range.lowerBound), endSeconds: seconds(range.upperBound),
                         speechStartSeconds: speechOffset, speechEndSeconds: speechOffset + length)
        }
        let scored = { (scores: [Double]) in
            zip(windows.ranges, scores).map { range, score in
                EuphonaResult.ScoredWindow(startSeconds: seconds(range.lowerBound), endSeconds: seconds(range.upperBound), score: score)
            }
        }
        return EuphonaResult(
            modelVersion: Self.modelVersion,
            scoreProfile: profile,
            inputSeconds: audio.duration,
            speech: .init(seconds: speechOffset, segments: speechSegments),
            f0: f0,
            timbre: .init(score: timbreScore, windows: scored(timbre)),
            flow: flow,
            ease: ease,
            hnrDb: meanHNR(quality)
        )
    }

    /// The overall score these component scores give.
    public static func score(
        profile: ScoreProfile, timbreScore: Double, flow: Double, ease: Double, f0Hz: Double?
    ) -> ScoreBreakdown {
        Scoring.score(profile: profile, timbre: timbreScore, flow: flow, ease: ease, f0Hz: f0Hz)
    }

    private func f0Metrics(_ track: PitchTrack, segments: [Range<Int>]) -> EuphonaResult.F0Metrics {
        let windowSeconds = 0.05
        let voiced = track.voiced(minHz: settings.minF0Hz, maxHz: settings.maxF0Hz, minConfidence: settings.minConfidence)
        let duration = Double(segments.last?.upperBound ?? 0) / Double(Self.sampleRate)
        let windowCount = max(1, Int((duration / windowSeconds).rounded(.up)))
        var sums = [Double](repeating: 0, count: windowCount), counts = [Int](repeating: 0, count: windowCount)
        var all: [Double] = []
        for (index, value) in voiced.enumerated() {
            guard let value else { continue }
            let centre = Double(index * PitchTrack.hop) + PitchTrack.centreOffset
            guard segments.contains(where: { Double($0.lowerBound) <= centre && centre < Double($0.upperBound) }) else { continue }
            let time = PitchTrack.time(ofFrame: index)
            let w = min(windowCount - 1, Int(time / windowSeconds))
            sums[w] += Double(value)
            counts[w] += 1
            all.append(Double(value))
        }
        let mean = all.isEmpty ? nil : all.reduce(0, +) / Double(all.count)
        let std = mean.map { m in (all.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(all.count)).squareRoot() }
        return .init(
            standardDeviationHz: std,
            windows: (0..<windowCount).map { w in
                .init(startSeconds: Double(w) * windowSeconds, endSeconds: Double(w + 1) * windowSeconds,
                      f0Hz: counts[w] > 0 ? sums[w] / Double(counts[w]) : nil)
            })
    }

    private func meanHNR(_ quality: VoiceQuality) -> Double? {
        let values = quality.hnrWindows().compactMap(\.db).map(Double.init)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    // MARK: Speech detection

    /// Speech intervals on the input timeline.
    public func detectSpeech(_ audio: PCMBuffer) throws -> [SpeechInterval] {
        let samples = try Self.prepare(audio)
        return try speech.segments(samples).map {
            SpeechInterval(start: Double($0.lowerBound) / Double(Self.sampleRate), end: Double($0.upperBound) / Double(Self.sampleRate))
        }
    }

    // MARK: Voice quality

    /// Predicted listener-rated severity (CAPE-V, 0–100) at or above which rest is suggested.
    static let severityLine = 35.0

    /// Voice quality from acoustic measures, with a check of the recording itself. Throws
    /// `.noSpeech` when there is too little voiced speech to measure at all.
    public func voiceQuality(
        _ audio: PCMBuffer,
        progress: (@Sendable (AnalysisProgress) -> Void)? = nil
    ) throws -> VoiceQualityEstimate {
        let report = { (stage: AnalysisStage) in
            progress?(AnalysisProgress(kind: .voiceQuality, stage: stage, stageFraction: 0))
        }
        let samples = try Self.prepare(audio)
        report(.detectingSpeech)
        let segments = try speech.segments(samples)
        guard !segments.isEmpty else { throw AnalysisError.noSpeech }
        report(.analyzingPitch)
        let track = try pitch.track(samples)
        report(.measuringVoice)
        let features = VoiceQuality(samples: samples, segments: segments, pitch: track).features()
        let inputs = features.modelInputs
        guard inputs.allSatisfy(\.isFinite) else { throw AnalysisError.noSpeech }
        report(.scoringVoiceQuality)
        let severity = Double(try quality.run([("features", .floats(Tensor(inputs, shape: [1, inputs.count])))],
                                              outputs: ["severity"])[0].values[0])
        report(.completed)
        return VoiceQualityEstimate(
            score: 100 - severity, threshold: 100 - Self.severityLine, features: features,
            check: .measure(samples, speech: segments, voicedFraction: features.voicedFraction, sampleRate: Self.sampleRate))
    }

    // MARK: Audio

    /// 16 kHz mono samples quantized to 16 bits, the form every model was trained on.
    static func prepare(_ audio: PCMBuffer) throws -> [Float] {
        guard audio.sampleRate > 0, audio.channels > 0 else {
            throw AnalysisError(kind: .unsupportedFormat, message: "invalid sample rate or channel count")
        }
        guard !audio.samples.isEmpty else { throw AnalysisError.noSpeech }
        var mono = audio.samples
        if audio.channels > 1 {
            mono = stride(from: 0, to: audio.samples.count - audio.channels + 1, by: audio.channels).map { start in
                audio.samples[start..<start + audio.channels].reduce(0, +) / Float(audio.channels)
            }
        }
        if audio.sampleRate != sampleRate { mono = try resample(mono, from: audio.sampleRate, to: sampleRate) }
        return mono.map { (max(-1, min(1, $0)) * 32767).rounded() / 32768 }
    }

    static func resample(_ samples: [Float], from rate: Int, to targetRate: Int) throws -> [Float] {
        guard let source = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1),
              let target = AVAudioFormat(standardFormatWithSampleRate: Double(targetRate), channels: 1),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(
                Double(samples.count) * Double(targetRate) / Double(rate) + 1024))
        else { throw AnalysisError(kind: .unsupportedFormat, message: "cannot convert \(rate) Hz audio") }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw AnalysisError(kind: .unsupportedFormat, message: error.localizedDescription) }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
