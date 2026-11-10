import Foundation
import SwiftData
import Testing
@testable import EuphonaKit

struct CoachTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let baseline = VoiceBaseline(speakingF0Hz: 130, timbre: 20, flow: 70, score: 25)

    func attempt(_ skill: Skill, _ level: Int, _ outcome: Outcome, _ minute: Int, id: String = "x",
                 value: Double? = nil, pass: Double? = nil) -> AttemptSummary {
        AttemptSummary(date: Self.start.addingTimeInterval(Double(minute) * 60), exerciseID: id, skill: skill, level: level,
                       outcome: outcome, value: value, pass: pass)
    }

    func center(_ target: PitchTarget) -> Double {
        let range = target.range(at: 0)
        return (range.lowerBound * range.upperBound).squareRoot()
    }

    @Test func everySkillHasAContinuousLadderAndEveryExerciseHasAUniqueID() {
        for goal in VoiceGoal.allCases {
            let plan = CoachPlan(goal: goal, baseline: Self.baseline, attempts: [])
            #expect(Set(plan.exercises.map(\.id)).count == plan.exercises.count)
            for skill in Skill.allCases {
                let levels = plan.exercises.filter { $0.skill == skill }.map(\.level).sorted()
                #expect(levels == Array(1...levels.count))
            }
        }
    }

    @Test func pitchBandsStartFromTheOwnPitchAndMoveTowardTheGoal() {
        let plan = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [])
        guard case .pitch(let first) = plan.exercise(.pitch, level: 1).tool,
              case .pitch(let last) = plan.exercise(.pitch, level: 4).tool else { Issue.record("not pitch"); return }
        #expect(abs(center(first) - 130 * pow(2, 1.0 / 12)) < 0.1)
        #expect(abs(center(last) - 130 * pow(2, 4.0 / 12)) < 0.1)
        // Already in the goal's range: the typical band.
        let there = CoachPlan(goal: .feminine, baseline: VoiceBaseline(speakingF0Hz: 220, timbre: 60, flow: 70, score: 60), attempts: [])
        #expect(there.exercise(.pitch, level: 1).tool == .pitch(.typicalBand(for: .feminine)))
        // Masculine bands go down.
        let down = CoachPlan(goal: .masculine, baseline: VoiceBaseline(speakingF0Hz: 200, timbre: 20, flow: 70, score: 30), attempts: [])
        guard case .pitch(let lower) = down.exercise(.pitch, level: 1).tool else { return }
        #expect(center(lower) < 200)
    }

    @Test func goalsStartAboveTheBaselineAndRiseWithRecentResults() {
        let plan = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [])
        // Timbre 20 at the start: the level-3 goal is 20 + 8 + 2 × 5, not the generic 55.
        #expect(plan.exercise(.resonance, level: 3).goal.pass == 38)
        let hold = plan.exercise(.pitch, level: 1)
        #expect(hold.goal.pass == 60)
        let tried = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [
            attempt(.pitch, 1, .passed, 0, id: hold.id, value: 80), attempt(.pitch, 1, .passed, 1, id: hold.id, value: 82),
        ])
        #expect(tried.exercise(hold.id)?.goal.pass == 87)
    }

    @Test func outcomesFollowTheGoalsThresholds() {
        let plan = CoachPlan(goal: .feminine, baseline: nil, attempts: [])
        let hold = plan.exercise(.pitch, level: 1)
        #expect(hold.outcome(AttemptMetrics(seconds: 30, onTarget: 65)) == .passed)
        #expect(hold.outcome(AttemptMetrics(seconds: 30, onTarget: 50)) == .close)
        #expect(hold.outcome(AttemptMetrics(seconds: 30, onTarget: 10)) == .missed)
        #expect(hold.outcome(AttemptMetrics(seconds: 30)) == .unmeasured)
        let straw = plan.exercise("straw")!
        #expect(straw.outcome(AttemptMetrics(seconds: 60)) == .passed)
        #expect(straw.outcome(AttemptMetrics(seconds: 20)) == .missed)
    }

    @Test func levelsFollowPassesMissesAndLeaps() {
        var attempts = [attempt(.pitch, 1, .passed, 0), attempt(.pitch, 1, .close, 1), attempt(.pitch, 1, .passed, 2)]
        #expect(Mastery.progress(attempts)[.pitch]?.level == 2)
        attempts += [attempt(.pitch, 2, .missed, 3), attempt(.pitch, 2, .missed, 4)]
        #expect(Mastery.progress(attempts)[.pitch]?.level == 1)
        // A pass far above the goal moves up at once.
        #expect(Mastery.progress([attempt(.pitch, 1, .passed, 0, value: 99, pass: 60)])[.pitch]?.level == 2)
        // A pass at a level the coach moved up to counts there.
        #expect(Mastery.progress([attempt(.pitch, 3, .passed, 0)])[.pitch].map { ($0.level, $0.passes) } ?? (0, 0) == (3, 1))
        // A miss at a higher level doesn't.
        #expect(Mastery.progress([attempt(.pitch, 3, .missed, 0)])[.pitch]?.level == 1)
    }

    @Test func passingTheTopLevelCompletesTheSkillAndMovesTheFocus() {
        var attempts: [AttemptSummary] = []
        for level in 1...ExerciseLibrary.levels(of: .pitch) {
            attempts += [attempt(.pitch, level, .passed, level * 2), attempt(.pitch, level, .passed, level * 2 + 1)]
        }
        let plan = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: attempts)
        #expect(plan.progress[.pitch]?.isComplete == true && plan.progress[.pitch]?.fraction == 1)
        #expect(plan.focus == .resonance)
        #expect(plan.lesson(checkIn: nil, day: Self.start).steps.last == .review(.pitch))
    }

    @Test func analysesPlaceEachSkillAndPassesMoveOnFromThere() {
        #expect(CoachPlan(goal: .feminine, baseline: nil, attempts: []).progress.values.allSatisfy { $0.level == 1 })
        let low = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [])
        // 130 Hz is about a fifth of the way to the feminine pitch; timbre 20; flow 70 but score 25.
        #expect(low.placement == [.pitch: 1, .resonance: 1, .intonation: 2, .carryOver: 1])
        let along = VoiceBaseline(speakingF0Hz: 165, timbre: 60, flow: 85, score: 70)
        let placed = CoachPlan(goal: .feminine, baseline: along, attempts: [])
        #expect(placed.placement == [.pitch: 3, .resonance: 3, .intonation: 3, .carryOver: 3])
        // The same voice, trained the other way, starts low.
        #expect(CoachPlan(goal: .masculine, baseline: VoiceBaseline(speakingF0Hz: 165, timbre: 40, flow: 85, score: 30),
                          attempts: []).placement[.pitch] == 2)
        // Placing never completes a skill; two passes at the placed level move it up.
        #expect(placed.progress[.carryOver].map { ($0.level, $0.isComplete) } ?? (0, true) == (3, false))
        let passed = CoachPlan(goal: .feminine, baseline: along, attempts: [attempt(.pitch, 3, .passed, 0), attempt(.pitch, 3, .passed, 1)])
        #expect(passed.progress[.pitch]?.level == 4)
        #expect(placed.lesson(checkIn: nil, day: Self.start).steps.filter { $0 == .focus }.count == 2)
    }

    @Test func painGivesARestLesson() {
        let plan = CoachPlan(goal: .masculine, baseline: nil, attempts: [])
        let rest = plan.lesson(checkIn: CheckInSummary(comfort: 4, pain: true))
        #expect(rest.isRest && rest.steps.allSatisfy { plan.exercise(for: $0).tool == .timed })
    }

    @Test func todaysRequestsMoveTheLessonAndExpireTomorrow() {
        let at = { (minute: Double) in Self.start.addingTimeInterval(minute * 60) }
        let requests = PlanRequests([PlanRequest(.harder, date: at(0)), PlanRequest(.harder, date: at(1)),
                                     PlanRequest(.harder, date: at(2))], on: Self.start)
        #expect(requests.levelShift == PlanRequests.maximumShift)
        let harder = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [], requests: requests)
        #expect(harder.exercise(for: .focus).level == 1 + PlanRequests.maximumShift)
        // The earned level never goes below the first.
        let easier = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [],
                               requests: PlanRequests([PlanRequest(.easier, date: at(0))], on: Self.start))
        #expect(easier.exercise(for: .focus).level == 1)
        let focused = PlanRequests([PlanRequest(.harder, date: at(0)), PlanRequest(.focus, skill: .intonation, date: at(1))], on: Self.start)
        #expect(focused.focus == .intonation && focused.levelShift == 0)
        let plan = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [], requests: focused)
        #expect(plan.focus == .intonation && plan.lesson(checkIn: nil, day: Self.start).steps.last == .review(.resonance))
        let rest = PlanRequests([PlanRequest(.rest, date: at(0))], on: Self.start)
        #expect(CoachPlan(goal: .feminine, baseline: nil, attempts: [], requests: rest).lesson(checkIn: nil).isRest)
        #expect(PlanRequests([PlanRequest(.rest, date: at(0)), PlanRequest(.reset, date: at(1))], on: Self.start) == .none)
        #expect(PlanRequests([PlanRequest(.rest, date: at(0))], on: at(24 * 60)) == .none)
    }

    @Test func requestsThatCantMoveTheLessonChangeNothing() {
        let first = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [])
        #expect(!first.isChanged(by: PlanRequest(.easier)) && !first.isChanged(by: PlanRequest(.reset)))
        #expect(!first.isChanged(by: PlanRequest(.focus, skill: .pitch)))
        let harder = first.with(PlanRequest(.harder))
        #expect(first.isChanged(by: PlanRequest(.harder)) && harder.focusLevel == 2)
        #expect(harder.isChanged(by: PlanRequest(.reset)) && harder.with(PlanRequest(.reset)).focusLevel == 1)
        let top = CoachPlan(goal: .feminine, baseline: VoiceBaseline(speakingF0Hz: 200, timbre: 90, flow: 90, score: 90), attempts: [])
        #expect(top.focusLevel == 4 && !top.isChanged(by: PlanRequest(.harder)))
        #expect(first.isChanged(by: PlanRequest(.rest)) && !first.with(PlanRequest(.rest)).isChanged(by: PlanRequest(.rest)))
        // Before the first analysis there is no lesson to change.
        let none = CoachPlan(goal: .feminine, baseline: nil, attempts: [])
        #expect(PlanRequest.Kind.allCases.allSatisfy { !none.isChanged(by: PlanRequest($0, skill: .resonance)) })
    }

    @Test func aClearPassGoesHarderAndAdjustmentsStayInsideTheLibrary() {
        let plan = CoachPlan(goal: .feminine, baseline: Self.baseline, attempts: [])
        let first = plan.exercise(.resonance, level: 1)
        let top = plan.exercise(.resonance, level: 99)
        #expect(plan.adjustment(after: .passed, exercise: first, value: first.goal.pass + 25, tries: 1) == .harder)
        #expect(plan.adjustment(after: .passed, exercise: first, value: first.goal.pass + 5, tries: 1) == .next)
        #expect(plan.adjustment(after: .passed, exercise: top, value: 100, tries: 1) == .next)
        #expect(plan.adjustment(after: .missed, exercise: top, value: 0, tries: 2) == .easier)
        #expect(plan.apply(.easier, to: first) == first)
        #expect(plan.apply(.harder, to: top) == top)
        #expect(plan.apply(.next, to: first) == nil)
    }

    @Test func baselinesAreMediansOfTheLatestAnalyses() {
        let analyses = [
            VoiceBaseline(speakingF0Hz: 150, timbre: 40, flow: 70, score: 30),
            VoiceBaseline(speakingF0Hz: 140, timbre: 30, flow: 60, score: 20),
            VoiceBaseline(speakingF0Hz: nil, timbre: 50, flow: 80, score: 40),
            VoiceBaseline(speakingF0Hz: 100, timbre: 0, flow: 0, score: 0),
        ]
        let baseline = VoiceBaseline.median(of: analyses)
        #expect(baseline == VoiceBaseline(speakingF0Hz: 145, timbre: 40, flow: 70, score: 30))
        #expect(VoiceBaseline.median(of: []) == nil)
    }

    @MainActor @Test func attemptsAndCheckInsAreStored() throws {
        let container = try ModelContainer(for: Schema(HistorySchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = HistoryStore(context: container.mainContext)
        let hold = CoachPlan(goal: .feminine, baseline: nil, attempts: []).exercise(.pitch, level: 1)
        try store.addAttempt(hold, metrics: AttemptMetrics(seconds: 30, onTarget: 70), outcome: .passed, goal: .feminine)
        let saved = try #require(try store.coachAttempts(goal: .feminine).first)
        #expect(saved.summary.value == 70 && saved.summary.pass == 60)
        #expect(try store.coachAttempts(goal: .masculine).isEmpty)
        try store.addCheckIn(comfort: 2, pain: true)
        #expect(try store.checkIn()?.summary.needsRest == true)
        try store.addRequest(PlanRequest(.focus, skill: .resonance))
        #expect(try store.requests().focus == .resonance)
    }
}
