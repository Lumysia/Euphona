import Foundation

/// Brings quiet unprocessed recordings up to a fixed speech level.
///
/// Measurement mode turns off the input's gain control, so speech arrives far quieter than with
/// voice processing. Silero VAD and the voice quality model both depend on
/// level (VAD finds no speech at −40 dBFS peaks), so measurement recordings are scaled to the level
/// the models were tuned on. Only ever boosts, and never boosts what is only room noise.
public struct SpeechLevel: Sendable {
    /// The loud end of speech (99th percentile of |sample|) is brought to this.
    public static let target: Float = 0.25
    public static let maximumGain: Float = 30
    /// Below this the loudest sound so far is taken to be room noise, and nothing is boosted.
    public static let noiseFloor: Float = 0.002

    private var reference: Float = 0

    public init() {}

    /// The gain for everything observed so far.
    public var gain: Float {
        guard reference >= Self.noiseFloor else { return 1 }
        return min(max(Self.target / reference, 1), Self.maximumGain)
    }

    /// Takes in a stretch of audio; the reference only ever rises, so the gain only ever falls.
    public mutating func observe(_ samples: [Float]) {
        reference = max(reference, Self.loudLevel(samples))
    }

    public static func loudLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let magnitudes = samples.map(abs).sorted()
        return magnitudes[min(magnitudes.count - 1, Int(Double(magnitudes.count) * 0.99))]
    }

    public static func apply(_ gain: Float, to samples: [Float]) -> [Float] {
        gain == 1 ? samples : samples.map { min(max($0 * gain, -1), 1) }
    }
}
