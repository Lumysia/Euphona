import Foundation
import SwiftData

/// One try of a coach exercise.
@Model
public final class CoachAttempt {
    public var date: Date = Date.now
    public var exerciseID: String = ""
    public var skillRaw: String?
    public var level: Int = 1
    public var outcomeRaw: String = Outcome.unmeasured.rawValue
    /// `AttemptMetrics` as JSON.
    public var metricsJSON: Data?
    /// The voice goal the exercise was set for.
    public var goalRaw: String = VoiceGoal.feminine.rawValue
    /// The judged measure and the goal it had to reach, both goal-aligned 0...100.
    public var value: Double?
    public var passLine: Double?

    public init(exercise: Exercise, metrics: AttemptMetrics, outcome: Outcome, goal: VoiceGoal, date: Date = .now) {
        self.date = date
        exerciseID = exercise.id
        skillRaw = exercise.skill?.rawValue
        level = exercise.level
        outcomeRaw = outcome.rawValue
        metricsJSON = try? JSONEncoder().encode(metrics)
        goalRaw = goal.rawValue
        value = metrics.value(exercise.goal.measure, plannedSeconds: exercise.seconds)
        passLine = exercise.goal.pass
    }

    public var outcome: Outcome { Outcome(rawValue: outcomeRaw) ?? .unmeasured }
    public var goal: VoiceGoal { VoiceGoal(rawValue: goalRaw) ?? .feminine }
    public var metrics: AttemptMetrics? { metricsJSON.flatMap { try? JSONDecoder().decode(AttemptMetrics.self, from: $0) } }

    public var summary: AttemptSummary {
        AttemptSummary(date: date, exerciseID: exerciseID, skill: skillRaw.flatMap(Skill.init), level: level, outcome: outcome,
                       value: value, pass: passLine)
    }
}

/// How the voice felt before a lesson.
@Model
public final class VoiceCheckIn {
    public var date: Date = Date.now
    public var comfort: Int = 3
    public var pain: Bool = false

    public init(comfort: Int, pain: Bool, date: Date = .now) {
        self.date = date
        self.comfort = comfort
        self.pain = pain
    }

    public var summary: CheckInSummary { CheckInSummary(comfort: comfort, pain: pain) }
}

/// A lesson taken to its end.
@Model
public final class CompletedLesson {
    public var date: Date = Date.now
    public var goalRaw: String = VoiceGoal.feminine.rawValue

    public init(goal: VoiceGoal, date: Date = .now) {
        self.date = date
        goalRaw = goal.rawValue
    }
}

/// One message of the conversation with the coach: what the learner said, or what the coach said
/// in reply or after an attempt. Kept so later reviews can build on it.
@Model
public final class CoachNote {
    public var date: Date = Date.now
    /// The exercise an attempt review is about; empty in conversation.
    public var exerciseID: String = ""
    public var text: String = ""
    public var fromLearner: Bool = false
    /// A plan change the coach suggested with this message; it only happens when the learner confirms.
    public var suggestionKindRaw: String?
    public var suggestionSkillRaw: String?

    public init(exerciseID: String = "", text: String, fromLearner: Bool = false, suggestion: PlanRequest? = nil, date: Date = .now) {
        self.date = date
        self.exerciseID = exerciseID
        self.text = text
        self.fromLearner = fromLearner
        suggestionKindRaw = suggestion?.kind.rawValue
        suggestionSkillRaw = suggestion?.skill?.rawValue
    }

    public var suggestion: PlanRequest? {
        suggestionKindRaw.flatMap(PlanRequest.Kind.init(rawValue:)).map { PlanRequest($0, skill: suggestionSkillRaw.flatMap(Skill.init(rawValue:)), date: date) }
    }
}

/// A `PlanRequest` as stored.
@Model
public final class CoachRequest {
    public var date: Date = Date.now
    public var kindRaw: String = PlanRequest.Kind.reset.rawValue
    public var skillRaw: String?

    public init(_ request: PlanRequest) {
        date = request.date
        kindRaw = request.kind.rawValue
        skillRaw = request.skill?.rawValue
    }

    public var request: PlanRequest? {
        PlanRequest.Kind(rawValue: kindRaw).map { PlanRequest($0, skill: skillRaw.flatMap(Skill.init), date: date) }
    }
}
