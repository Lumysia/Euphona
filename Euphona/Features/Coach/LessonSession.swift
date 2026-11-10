import Foundation
import Observation
import EuphonaKit

extension VoiceBaseline {
    /// The goal-aligned values of one analysis.
    init(_ record: AnalysisRecord, goal: VoiceGoal) {
        self.init(speakingF0Hz: record.speakingF0Hz, timbre: goal == .feminine ? record.timbreScore : 100 - record.timbreScore,
                  flow: record.flowScore, score: record.finalScore)
    }

    /// From the latest analyses toward `goal`; `records` newest first.
    static func latest(_ records: [AnalysisRecord], goal: VoiceGoal) -> [VoiceBaseline] {
        records.filter { $0.scoreProfile == goal.scoreProfile }.prefix(analysesUsed).map { VoiceBaseline($0, goal: goal) }
    }
}

extension CoachPlan {
    /// The plan as the stored history has it now. `records` newest first.
    @MainActor
    init(goal: VoiceGoal, records: [AnalysisRecord], attempts: [CoachAttempt], requests: [CoachRequest]) {
        self.init(goal: goal, baseline: .median(of: VoiceBaseline.latest(records, goal: goal)),
                  attempts: attempts.filter { $0.goal == goal }.map(\.summary),
                  requests: PlanRequests(requests.compactMap(\.request)))
    }
}

/// One lesson in progress: check-in, then each step's explanation, try and review. The plan is
/// rebuilt after every try, so the next step's level and goal already reflect it.
@MainActor @Observable
final class LessonSession {
    enum Phase: Equatable { case checkIn, explain, trying, reviewing, finished }

    let goal: VoiceGoal
    let started = Date.now
    private(set) var plan: CoachPlan
    private(set) var lesson: Lesson
    private(set) var stepIndex = 0
    private(set) var exercise: Exercise
    private(set) var phase: Phase
    /// Attempts at the current step.
    private(set) var tries = 0
    private(set) var outcome: Outcome?
    private(set) var value: Double?
    /// Nil while the coach is still thinking.
    private(set) var review: CoachReview?
    /// What was said in a free-speaking try, when the system could transcribe it.
    private(set) var transcript: Transcript?
    /// Every outcome of this lesson, for the summary.
    private(set) var results: [(exercise: Exercise, outcome: Outcome)] = []
    /// The prompt for speaking freely, a different one each lesson.
    let talkPrompt = TalkPrompts.prompt(Int.random(in: 0..<TalkPrompts.count))

    // The current try's tools, new for every try so each measures only that try.
    private(set) var pitch = PitchMonitor()
    private(set) var timbre = TimbreMonitor()
    private(set) var resonance = ResonanceMonitor()

    private var attempts: [AttemptSummary]
    /// The latest analyses toward the goal, newest first; recorded steps add to them.
    private var analyses: [VoiceBaseline]
    private var requests: PlanRequests

    init(goal: VoiceGoal, analyses: [VoiceBaseline], attempts: [AttemptSummary], requests: PlanRequests, checkIn: CheckInSummary?) {
        self.goal = goal
        self.analyses = analyses
        self.attempts = attempts
        self.requests = requests
        let plan = CoachPlan(goal: goal, baseline: .median(of: analyses), attempts: attempts, requests: requests)
        let lesson = plan.lesson(checkIn: checkIn)
        self.plan = plan
        self.lesson = lesson
        exercise = plan.exercise(for: lesson.steps[0])
        phase = checkIn == nil ? .checkIn : .explain
    }

    var stepCount: Int { lesson.steps.count }

    func checkIn(_ checkIn: CheckInSummary) {
        lesson = plan.lesson(checkIn: checkIn)
        exercise = plan.exercise(for: lesson.steps[0])
        phase = .explain
    }

    func beginTry() {
        pitch = PitchMonitor()
        timbre = TimbreMonitor()
        resonance = ResonanceMonitor()
        outcome = nil
        value = nil
        review = nil
        transcript = nil
        phase = .trying
    }

    /// Judges and stores the try, rebuilds the plan, then asks the coach. The written review shows
    /// at once when no model is used; a model's review replaces the wait when it arrives, or the
    /// written one if it fails.
    func finish(_ metrics: AttemptMetrics, store: HistoryStore, choice: CoachModelChoice,
                snapshot: @escaping @MainActor () -> LanguageCoach.Snapshot, errors: ErrorCenter) async {
        guard phase == .trying else { return }
        let outcome = exercise.outcome(metrics)
        let value = metrics.value(exercise.goal.measure, plannedSeconds: exercise.seconds)
        tries += 1
        self.outcome = outcome
        self.value = value
        results.append((exercise, outcome))
        phase = .reviewing
        errors.attempt(.errorChangeFailed) { try store.addAttempt(exercise, metrics: metrics, outcome: outcome, goal: goal) }

        attempts.append(AttemptSummary(date: .now, exerciseID: exercise.id, skill: exercise.skill, level: exercise.level,
                                       outcome: outcome, value: value, pass: exercise.goal.pass))
        if let score = metrics.score, let timbre = metrics.timbre, let flow = metrics.flow {
            analyses.insert(VoiceBaseline(speakingF0Hz: metrics.speakingF0Hz, timbre: timbre, flow: flow, score: score), at: 0)
        }
        let judged = exercise
        rebuildPlan()

        let context = ReviewContext(exercise: judged, metrics: metrics, outcome: outcome, tries: tries, goal: goal, plan: plan)
        let written = WrittenCoach.review(context)
        guard LanguageCoach.isAvailable(choice) else { review = written; return }
        let modelReview = await LanguageCoach.review(context, snapshot: snapshot(), choice: choice)
        guard phase == .reviewing, exercise.id == judged.id else { return }
        review = modelReview ?? written
        if let modelReview { try? store.addNote(modelReview.message, exerciseID: judged.id) }
    }

    private func rebuildPlan() {
        plan = CoachPlan(goal: goal, baseline: .median(of: analyses), attempts: attempts, requests: requests)
    }

    /// Follows something the learner asked for mid-lesson: rest turns the rest of the lesson into
    /// rest, easier or harder moves the current skill exercise a level at once.
    func follow(_ request: PlanRequest, requests: PlanRequests) {
        self.requests = requests
        rebuildPlan()
        switch request.kind {
        case .rest where !lesson.isRest:
            lesson = plan.lesson(checkIn: nil)
            stepIndex = 0
            moveTo(plan.exercise(for: lesson.steps[0]))
        case .easier, .harder:
            guard let skill = exercise.skill else { return }
            moveTo(plan.exercise(skill, level: exercise.level + (request.kind == .harder ? 1 : -1)))
        default:
            break
        }
    }

    private func moveTo(_ next: Exercise) {
        exercise = next
        tries = 0
        review = nil
        outcome = nil
        value = nil
        transcript = nil
        phase = .explain
    }

    func transcribe(_ audio: PCMBuffer, speechSeconds: Double) {
        let exerciseID = exercise.id
        Task {
            let transcript = await Transcript.of(audio, speechSeconds: speechSeconds)
            guard exercise.id == exerciseID, phase == .reviewing || phase == .trying else { return }
            self.transcript = transcript
        }
    }

    /// Where an adjustment leads from here: the same or a neighbouring exercise, the lesson's next
    /// step as the plan now has it, or nil at the end of the lesson.
    func destination(of adjustment: Adjustment) -> Exercise? {
        if let next = plan.apply(adjustment, to: exercise) { return next }
        let following = stepIndex + 1
        return following < lesson.steps.count ? plan.exercise(for: lesson.steps[following]) : nil
    }

    /// Follows the review's choice.
    func follow(_ adjustment: Adjustment) {
        if let next = plan.apply(adjustment, to: exercise) {
            if next.id != exercise.id { tries = 0 }
            exercise = next
            if adjustment == .again { beginTry() } else { phase = .explain }
            return
        }
        stepIndex += 1
        tries = 0
        guard stepIndex < lesson.steps.count else { phase = .finished; return }
        exercise = plan.exercise(for: lesson.steps[stepIndex])
        phase = .explain
    }

    /// The choices offered after a review: the coach's own first, then the sensible others.
    var choices: [Adjustment] {
        guard let review else { return [] }
        var options = [review.adjustment]
        let others: [Adjustment] = outcome == .passed ? [.next] : [.next, .again]
        for other in others where !options.contains(other) { options.append(other) }
        return options
    }
}
