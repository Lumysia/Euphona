import EuphonaKit
import SwiftUI

/// What the coach says after an attempt, and what comes next.
struct CoachReview: Equatable {
    var message: String
    var adjustment: Adjustment
    /// Written by a language model rather than the built-in rules.
    var byModel = false
}

/// Everything a reviewer may look at for one attempt.
struct ReviewContext: Sendable {
    var exercise: Exercise
    var metrics: AttemptMetrics
    var outcome: Outcome
    /// This step's attempts so far, this one included.
    var tries: Int
    var goal: VoiceGoal
    /// The plan rebuilt with this attempt.
    var plan: CoachPlan

    var value: Double? { metrics.value(exercise.goal.measure, plannedSeconds: exercise.seconds) }
}

/// The built-in coach: the plan's rule for what comes next, and a sentence built from the
/// measurement and the exercise's own tip.
enum WrittenCoach {
    static func rule(_ context: ReviewContext) -> Adjustment {
        context.plan.adjustment(after: context.outcome, exercise: context.exercise, value: context.value, tries: context.tries)
    }

    static func review(_ context: ReviewContext) -> CoachReview {
        let exercise = context.exercise
        let adjustment = rule(context)
        let goal = exercise.describe(exercise.goal.pass)
        let message: String
        switch (context.outcome, context.value) {
        case (.passed, let value?) where adjustment == .harder:
            message = String(localized: .coachReviewLeap(exercise.describe(value), goal))
        case (.passed, _) where exercise.tool == .timed:
            message = String(localized: .coachReviewWarmedUp)
        case (.passed, let value?):
            message = String(localized: .coachReviewPassed(exercise.describe(value), goal))
        case (.close, let value?):
            message = String(localized: .coachReviewClose(exercise.describe(value), goal, exercise.tip))
        case (.missed, let value?):
            message = String(localized: .coachReviewMissed(exercise.describe(value), goal, exercise.tip))
        default:
            message = String(localized: .coachReviewUnmeasured)
        }
        return CoachReview(message: message, adjustment: adjustment)
    }

    /// A model may pick its own next step, within what the outcome allows: after a pass only on or
    /// harder, never harder after a miss, and warm-ups only repeat or move on.
    static func bounded(_ proposed: Adjustment, _ context: ReviewContext) -> Adjustment {
        let rule = rule(context)
        switch proposed {
        case .again where context.outcome == .passed, .easier where context.outcome == .passed: return rule
        case .harder where context.outcome != .passed || context.exercise.skill == nil: return rule
        case .easier where context.exercise.skill == nil: return rule
        case .again where context.tries >= 4: return .next
        default: return proposed
        }
    }
}
