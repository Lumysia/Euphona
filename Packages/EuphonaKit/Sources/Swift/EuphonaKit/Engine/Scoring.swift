import Foundation

/// The overall score, the same way for both voice goals:
///
///     Voice = 0.6 × Timbre + 0.4 × Pitch
///     Final = Voice × Fluency
///
/// Timbre and Pitch are goal-aligned 0...100 (higher is closer to the goal). Pitch moves evenly in
/// semitones between the typical masculine and feminine speaking pitch, so every step counts the same.
/// Fluency follows the lower of Flow (pace and pauses) and Ease (how little audible strain): 1 when
/// both are good, easing down to 0.8, so faults cost at most a fifth of the score and never cut it off. There are no caps and no thresholds: a small change in the voice
/// is a small change in the score, and 100 needs both timbre and pitch at the goal.
public enum Scoring {
    /// Typical masculine and feminine speaking pitch, the centers of `PitchTarget.typicalBand`.
    public static let masculinePitchHz = (85.0 * 155).squareRoot()
    public static let femininePitchHz = (165.0 * 255).squareRoot()
    /// Halfway between them in semitones: where the pitch chart turns from blue to pink.
    public static let pitchMidpointHz = (masculinePitchHz * femininePitchHz).squareRoot()

    public static let timbreWeight = 0.6
    public static let pitchWeight = 0.4
    /// Flow or ease at or above which fluency costs nothing, and at or below which it costs the most.
    public static let fluentLevel = 80.0
    public static let disfluentLevel = 30.0
    /// The most fluency can take away: Final never falls below this share of Voice.
    public static let fluencyFloor = 0.8

    /// Pitch progress toward the goal, 0...100, linear in semitones.
    public static func pitchProgress(_ hz: Double, goal: ScoreProfile) -> Double {
        guard hz > 0 else { return 0 }
        let feminine = 100 * log2(hz / masculinePitchHz) / log2(femininePitchHz / masculinePitchHz)
        let aligned = goal == .feminization ? feminine : 100 - feminine
        return min(max(aligned, 0), 100)
    }

    /// 1 for fluent speech, easing (smoothstep) to `fluencyFloor`.
    /// `level` is the lower of flow and ease.
    public static func fluency(_ level: Double) -> Double {
        let x = min(max((level - disfluentLevel) / (fluentLevel - disfluentLevel), 0), 1)
        return fluencyFloor + (1 - fluencyFloor) * x * x * (3 - 2 * x)
    }

    /// `timbre` is the model's feminine timbre score.
    public static func score(profile: ScoreProfile, timbre: Double, flow: Double, ease: Double, f0Hz: Double?) -> ScoreBreakdown {
        let alignedTimbre = min(max(profile == .feminization ? timbre : 100 - timbre, 0), 100)
        let pitch = f0Hz.flatMap { $0.isFinite && $0 > 0 ? pitchProgress($0, goal: profile) : nil }
        // Without a pitch, timbre alone carries the voice part.
        let voice = pitch.map { timbreWeight * alignedTimbre + pitchWeight * $0 } ?? alignedTimbre
        let fluency = fluency(min(flow, ease))
        return ScoreBreakdown(timbre: alignedTimbre, pitch: pitch, flow: flow, ease: ease, voice: voice,
                              fluency: fluency, finalScore: voice * fluency)
    }
}

/// How an overall score was reached, from its components.
public struct ScoreBreakdown: Sendable, Equatable {
    /// Goal-aligned timbre, 0...100.
    public var timbre: Double
    /// Goal-aligned pitch progress, 0...100; nil when no pitch was measured.
    public var pitch: Double?
    /// Pace and pauses, 0...100.
    public var flow: Double
    /// How little audible strain, 0...100.
    public var ease: Double
    /// The weighted timbre and pitch, before fluency.
    public var voice: Double
    /// `Scoring.fluencyFloor`...1.
    public var fluency: Double
    public var finalScore: Double

    /// Whichever of flow and ease sets the fluency: the lower one.
    public var fluencyMetric: ScoreMetric { ease < flow ? .ease : .flow }

    /// Points each component keeps from 100: what working on it could still add.
    public var losses: [(metric: ScoreMetric, points: Double)] {
        var out: [(ScoreMetric, Double)] = [(.timbre, (pitch == nil ? 1 : Scoring.timbreWeight) * (100 - timbre) * fluency)]
        if let pitch { out.append((.f0, Scoring.pitchWeight * (100 - pitch) * fluency)) }
        out.append((fluencyMetric, voice * (1 - fluency)))
        return out
    }

    /// Losing less than this in total, nothing holds the score back.
    public static let closeToFull = 5.0

    /// The component that costs the most points, or nil when the score is close to 100.
    public var bottleneck: ScoreMetric? {
        guard 100 - finalScore >= Self.closeToFull else { return nil }
        return losses.max { $0.points < $1.points }?.metric
    }
}
