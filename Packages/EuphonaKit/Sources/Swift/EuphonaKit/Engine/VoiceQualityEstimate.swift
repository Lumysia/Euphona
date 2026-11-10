import Foundation

/// The measures behind a Voice Quality estimate (see `VoiceQuality`).
public struct VoiceQualityFeatures: Codable, Sendable, Equatable {
    public var hnrDb: Double
    public var cppsDb: Double
    public var jitterLocal: Double
    public var jitterRap: Double
    public var jitterPpq5: Double
    public var shimmerLocal: Double
    public var shimmerApq3: Double
    public var shimmerApq5: Double
    public var f0Median: Double
    public var f0Iqr: Double
    public var f0Cv: Double
    public var voicedFraction: Double
    public var intensityMedian: Double
    public var intensityIqr: Double

    /// The model's inputs, in training order (tools/voice-model/train_quality.py `USED`): measures of
    /// the voice itself, not of who is speaking or how loud the microphone is.
    var modelInputs: [Float] {
        [hnrDb, cppsDb, jitterLocal, jitterRap, jitterPpq5, shimmerLocal, shimmerApq3, shimmerApq5, f0Cv,
         voicedFraction, intensityIqr].map(Float.init)
    }
}

/// Whether a recording is fit to judge voice quality from.
public struct RecordingCheck: Codable, Sendable, Equatable {
    public enum Issue: String, Codable, Sendable, CaseIterable {
        /// The input hit full scale, which adds roughness that isn't in the voice.
        case clipping
        /// Background noise close to the voice's level, which reads as breathiness.
        case noisy
        /// Too little voiced speech for stable measures.
        case tooLittleVoice
    }

    /// Share of speech samples at full scale.
    public var clippedFraction: Double
    /// Speech level over the level between speech, in dB.
    public var signalToNoiseDb: Double
    /// Seconds of speech that had a pitch.
    public var voicedSeconds: Double

    public static let maximumClippedFraction = 0.001
    public static let minimumSignalToNoiseDb = 15.0
    /// About 20 s of talking gives 15 s of detected speech, of which at least 10 s should be voiced.
    public static let minimumVoicedSeconds = 10.0

    public var issues: [Issue] {
        var issues: [Issue] = []
        if clippedFraction > Self.maximumClippedFraction { issues.append(.clipping) }
        if signalToNoiseDb < Self.minimumSignalToNoiseDb { issues.append(.noisy) }
        if voicedSeconds < Self.minimumVoicedSeconds { issues.append(.tooLittleVoice) }
        return issues
    }

    static func measure(_ samples: [Float], speech segments: [Range<Int>], voicedFraction: Double, sampleRate: Int) -> RecordingCheck {
        var inSpeech = [Bool](repeating: false, count: samples.count)
        for segment in segments { for i in segment.clamped(to: 0..<samples.count) { inSpeech[i] = true } }
        var speechEnergy = 0.0, speechCount = 0, pauseEnergy = 0.0, pauseCount = 0, clipped = 0
        for (index, sample) in samples.enumerated() {
            let value = Double(sample)
            if inSpeech[index] {
                speechEnergy += value * value
                speechCount += 1
                if abs(sample) >= 0.999 { clipped += 1 }
            } else {
                pauseEnergy += value * value
                pauseCount += 1
            }
        }
        let speechRMS = (speechEnergy / Double(max(speechCount, 1))).squareRoot()
        // Without any pause to measure, assume the room is quiet rather than fail the check.
        let pauseRMS = pauseCount > sampleRate / 10 ? (pauseEnergy / Double(pauseCount)).squareRoot() : speechRMS / 1_000
        let snr = 20 * log10(max(speechRMS, 1e-9) / max(pauseRMS, 1e-9))
        let speechSeconds = Double(speechCount) / Double(sampleRate)
        return RecordingCheck(clippedFraction: Double(clipped) / Double(max(speechCount, 1)), signalToNoiseDb: snr,
                              voicedSeconds: speechSeconds * voicedFraction)
    }
}

/// An estimate of how a voice sounds to listeners (roughness, breathiness, strain), from a model
/// trained on CAPE-V ratings. Not a diagnosis.
public struct VoiceQualityEstimate: Codable, Sendable, Equatable {
    /// 100 minus the predicted listener-rated severity.
    public var score: Double
    /// Below this the voice sounds strained or rough enough to suggest rest.
    public var threshold: Double
    public var features: VoiceQualityFeatures
    public var check: RecordingCheck

    public var suggestsRest: Bool { score < threshold }
}
