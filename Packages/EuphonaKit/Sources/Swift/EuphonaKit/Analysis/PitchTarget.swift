import Foundation

/// Where the voice should be: a fixed band, or a glide that rises from `low` to `high` and falls back
/// over `period` seconds, followed within a tolerance.
public enum PitchTarget: Sendable, Equatable, Codable {
    case band(low: Double, high: Double)
    case glide(low: Double, high: Double, period: Double, toleranceSemitones: Double)

    /// Typical speaking pitch of adult women and men (Baken & Orlikoff, *Clinical Measurement of
    /// Speech and Voice*): the default band for each voice goal.
    public static func typicalBand(for goal: VoiceGoal) -> PitchTarget {
        switch goal {
        case .feminine: .band(low: 165, high: 255)
        case .masculine: .band(low: 85, high: 155)
        }
    }

    /// The accepted range at `time` seconds since the start.
    public func range(at time: Double) -> ClosedRange<Double> {
        switch self {
        case let .band(low, high):
            return low...high
        case let .glide(low, high, period, tolerance):
            let phase = (time / period).truncatingRemainder(dividingBy: 1)
            let rise = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            // Glide evenly in semitones, the way the ear hears it.
            let center = low * pow(high / low, rise)
            let factor = pow(2, tolerance / 12)
            return center / factor...center * factor
        }
    }

    public func contains(_ hz: Double, at time: Double) -> Bool { range(at: time).contains(hz) }

    /// The outer bounds the target ever reaches, for chart ranges.
    public var bounds: ClosedRange<Double> {
        switch self {
        case let .band(low, high): low...high
        case let .glide(low, high, _, tolerance): low / pow(2, tolerance / 12)...high * pow(2, tolerance / 12)
        }
    }

    /// Share of the voiced samples that were on target, or nil without any.
    public static func share(_ samples: [(time: Double, hz: Double)], on target: PitchTarget) -> Double? {
        guard !samples.isEmpty else { return nil }
        return Double(samples.filter { target.contains($0.hz, at: $0.time) }.count) / Double(samples.count)
    }
}
