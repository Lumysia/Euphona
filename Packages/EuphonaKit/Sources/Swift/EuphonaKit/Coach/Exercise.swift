import Foundation

/// The skill path, in teaching order.
public enum Skill: String, CaseIterable, Codable, Sendable {
    case pitch, resonance, intonation, carryOver
}

/// The tool an exercise is tried with, set up for it.
public enum ExerciseTool: Equatable, Codable, Sendable {
    /// A timed, unmeasured warm-up or rest (semi-occluded vocal tract work, humming).
    case timed
    case pitch(PitchTarget)
    /// Live timbre; the goal is on the goal-aligned scale.
    case timbre
    /// Live resonance; the goal is on goal-aligned brightness.
    case resonance
    /// A short recorded reading, scored by a full analysis.
    case reading
    /// Speaking freely about a prompt, transcribed and scored.
    case conversation
}

/// What an attempt is judged on. Every measure is 0...100, higher is closer to the voice goal.
public enum Measure: String, Codable, Sendable {
    /// Share of voiced time on the pitch target.
    case onTarget
    case timbre
    case brightness
    /// Pace and pauses of a recorded reading (`SpeechFlow`).
    case flow
    /// The overall score of a recorded reading or conversation.
    case score
    /// A timed exercise done to the end.
    case completed
}

/// What one attempt measured. Scales are goal-aligned 0...100; nil when the tool did not measure it.
public struct AttemptMetrics: Codable, Sendable, Equatable {
    public var seconds: Double
    public var onTarget: Double?
    public var timbre: Double?
    public var brightness: Double?
    public var flow: Double?
    public var score: Double?
    public var speakingF0Hz: Double?

    public init(seconds: Double, onTarget: Double? = nil, timbre: Double? = nil, brightness: Double? = nil,
                flow: Double? = nil, score: Double? = nil, speakingF0Hz: Double? = nil) {
        self.seconds = seconds
        self.onTarget = onTarget
        self.timbre = timbre
        self.brightness = brightness
        self.flow = flow
        self.score = score
        self.speakingF0Hz = speakingF0Hz
    }

    public func value(_ measure: Measure, plannedSeconds: Double) -> Double? {
        switch measure {
        case .onTarget: onTarget
        case .timbre: timbre
        case .brightness: brightness
        case .flow: flow
        case .score: score
        case .completed: min(seconds / max(plannedSeconds, 1), 1) * 100
        }
    }
}

public enum Outcome: String, Codable, Sendable {
    case passed, close, missed
    /// The tool heard too little to judge; the attempt does not count either way.
    case unmeasured
}

public struct ExerciseGoal: Equatable, Codable, Sendable {
    public var measure: Measure
    public var pass: Double
    /// At or above this the attempt is close.
    public var close: Double

    public func outcome(_ metrics: AttemptMetrics, plannedSeconds: Double) -> Outcome {
        guard let value = metrics.value(measure, plannedSeconds: plannedSeconds) else { return .unmeasured }
        if value >= pass { return .passed }
        return value >= close ? .close : .missed
    }
}

/// One exercise from Euphona's library. Its words live in the string catalog under
/// `coach_ex_<key>_title`, `_steps` and `_why`.
public struct Exercise: Identifiable, Equatable, Sendable {
    /// Stable across goals and versions; stored with attempts.
    public var id: String
    /// The catalog key part: exercises that differ only by goal share their words where they can.
    public var key: String
    /// Nil for warm-ups and rest, which belong to no skill.
    public var skill: Skill?
    /// 1 is the easiest.
    public var level: Int
    public var tool: ExerciseTool
    public var seconds: Double
    public var goal: ExerciseGoal

    public func outcome(_ metrics: AttemptMetrics) -> Outcome { goal.outcome(metrics, plannedSeconds: seconds) }
}
