import Foundation

/// Speech flow: how evenly someone speaks, from pace and pauses only, never from voice or style.
/// `tools/voice-model/flow.py` measures the same way and set the limits on natural FLEURS speech in
/// 15 languages.
///
/// - Articulation rate: syllable peaks of the loudness envelope (`Prosody`) per second of speech.
/// - Pause share: the silent gaps between speech segments, over the span from the first speech to
///   the last.
///
/// Flow is 100 within what natural speech covers and falls smoothly beyond it, so only rushed or
/// halting speech costs anything. Slow speech has no limit of its own: a slow style is not a fault,
/// and very slow speech still shows in its pauses.
public enum SpeechFlow {
    /// (full flow up to here, none from here).
    static let rateLimit = (full: 5.4, none: 7.0)
    static let pauseLimit = (full: 0.28, none: 0.55)

    static func measure(samples: [Float], segments: [Range<Int>]) -> EuphonaResult.Flow {
        let sampleRate = Double(SpeechDetector.sampleRate)
        let speech = Double(segments.reduce(0) { $0 + $1.count }) / sampleRate
        let syllables = Prosody.syllables(Prosody.envelope(samples, segments))
        let span = Double((segments.last?.upperBound ?? 0) - (segments.first?.lowerBound ?? 0)) / sampleRate
        let gaps = zip(segments, segments.dropFirst()).reduce(0.0) { $0 + Double($1.1.lowerBound - $1.0.upperBound) } / sampleRate
        let rate = Double(syllables) / max(speech, 1e-3)
        let pauses = gaps / max(span, 1e-3)
        return .init(score: score(rate: rate, pauseShare: pauses), articulationRate: rate, pauseShare: pauses)
    }

    public static func score(rate: Double, pauseShare: Double) -> Double {
        let pace = rate > 0 ? fall(log(rate), full: log(rateLimit.full), none: log(rateLimit.none)) : 1
        return 100 * pace * fall(pauseShare, full: pauseLimit.full, none: pauseLimit.none)
    }

    /// 1 up to `full`, 0 from `none`, smoothstep between.
    private static func fall(_ value: Double, full: Double, none: Double) -> Double {
        let x = min(max((value - none) / (full - none), 0), 1)
        return x * x * (3 - 2 * x)
    }
}
