import Foundation

/// One judged try of an exercise, as the plan sees it.
public struct AttemptSummary: Sendable, Equatable {
    public var date: Date
    public var exerciseID: String
    public var skill: Skill?
    public var level: Int
    public var outcome: Outcome
    /// The judged measure (goal-aligned 0...100), when the tool measured it.
    public var value: Double?
    /// The goal it was judged against.
    public var pass: Double?

    public init(date: Date, exerciseID: String, skill: Skill?, level: Int, outcome: Outcome, value: Double? = nil, pass: Double? = nil) {
        self.date = date
        self.exerciseID = exerciseID
        self.skill = skill
        self.level = level
        self.outcome = outcome
        self.value = value
        self.pass = pass
    }

    /// Passed far enough above the goal to skip the second pass.
    var leaped: Bool {
        guard outcome == .passed, let value, let pass else { return false }
        return value >= pass + CoachPlan.leapMargin
    }
}

/// Where the voice is now, from the latest full analyses toward the voice goal: what every
/// target grows from.
public struct VoiceBaseline: Sendable, Equatable {
    public var speakingF0Hz: Double?
    /// Goal-aligned 0...100 (higher is closer to the goal).
    public var timbre: Double
    public var flow: Double
    public var score: Double

    public init(speakingF0Hz: Double?, timbre: Double, flow: Double, score: Double) {
        self.speakingF0Hz = speakingF0Hz
        self.timbre = timbre
        self.flow = flow
        self.score = score
    }

    /// Analyses averaged into the baseline: enough to steady it, few enough to follow progress.
    public static let analysesUsed = 3

    /// The median of the latest analyses, newest first; nil without any.
    public static func median(of latest: [VoiceBaseline]) -> VoiceBaseline? {
        let recent = Array(latest.prefix(analysesUsed))
        guard !recent.isEmpty else { return nil }
        func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return VoiceBaseline(speakingF0Hz: median(recent.compactMap(\.speakingF0Hz)), timbre: median(recent.map(\.timbre))!,
                             flow: median(recent.map(\.flow))!, score: median(recent.map(\.score))!)
    }
}

/// How far along one skill is.
public struct SkillProgress: Sendable, Equatable {
    public var level: Int
    /// Passes at the current level, toward the two that move it up.
    public var passes: Int
    public var levels: Int
    /// The top level passed twice.
    public var isComplete: Bool

    /// 0...1 along the skill.
    public var fraction: Double {
        isComplete ? 1 : (Double(level - 1) + Double(passes) / Double(Mastery.passesToLevelUp)) / Double(levels)
    }
}

/// Levels from attempts: two passes at the current level move it up, two misses in a row move it
/// down, and a pass far above the goal counts as both passes. Close and unmeasured tries leave it.
public enum Mastery {
    public static let passesToLevelUp = 2
    public static let missesToLevelDown = 2

    /// `placement` is where each skill starts before any attempt (level 1 when missing).
    public static func progress(_ attempts: [AttemptSummary], placement: [Skill: Int] = [:]) -> [Skill: SkillProgress] {
        var result: [Skill: SkillProgress] = [:]
        for skill in Skill.allCases {
            let levels = ExerciseLibrary.levels(of: skill)
            var progress = SkillProgress(level: placement[skill] ?? 1, passes: 0, levels: levels, isComplete: false)
            var misses = 0
            for attempt in attempts.sorted(by: { $0.date < $1.date }) where attempt.skill == skill && attempt.level >= progress.level {
                // A higher level is only tried after the coach moved up; a pass there settles it.
                if attempt.level > progress.level {
                    guard attempt.outcome == .passed, !progress.isComplete else { continue }
                    progress.level = attempt.level
                    progress.passes = 0
                }
                switch attempt.outcome {
                case .passed:
                    misses = 0
                    progress.passes += attempt.leaped ? passesToLevelUp : 1
                    if progress.passes >= passesToLevelUp {
                        if progress.level == levels { progress.isComplete = true; progress.passes = passesToLevelUp }
                        else { progress.level += 1; progress.passes = 0 }
                    }
                case .missed:
                    misses += 1
                    if misses >= missesToLevelDown, progress.level > 1, !progress.isComplete {
                        progress.level -= 1
                        progress.passes = 0
                        misses = 0
                    }
                case .close, .unmeasured:
                    break
                }
            }
            result[skill] = progress
        }
        return result
    }

    /// The skill being learned: the first on the path not yet complete, or the last one.
    public static func focus(_ progress: [Skill: SkillProgress]) -> Skill {
        Skill.allCases.first { progress[$0]?.isComplete != true } ?? .carryOver
    }
}

/// Where each skill starts, from the latest analyses: the measure its exercises judge, read on the
/// skill's levels (a quarter of the way to the goal starts a four-level skill at level 2). Placing
/// never completes a skill; the top level still has to be passed. Without analyses, every skill
/// starts at level 1.
public enum Placement {
    public static func levels(goal: VoiceGoal, baseline: VoiceBaseline?) -> [Skill: Int] {
        guard let baseline else { return [:] }
        var placement: [Skill: Int] = [:]
        for skill in Skill.allCases {
            let value: Double? = switch skill {
            case .pitch: baseline.speakingF0Hz.map { Scoring.pitchProgress($0, goal: goal.scoreProfile) }
            case .resonance: baseline.timbre
            // Intonation ends in reading for the overall score, so flow and score both have to be there.
            case .intonation: min(baseline.flow, baseline.score)
            case .carryOver: baseline.score
            }
            guard let value else { continue }
            let levels = ExerciseLibrary.levels(of: skill)
            placement[skill] = min(max(Int(value / 100 * Double(levels)) + 1, 1), levels)
        }
        return placement
    }
}

/// How today feels, asked before a lesson.
public struct CheckInSummary: Sendable, Equatable {
    /// 1 (strained, tired) to 5 (fresh).
    public var comfort: Int
    /// Pain, hoarseness or a sore throat.
    public var pain: Bool

    public init(comfort: Int, pain: Bool) {
        self.comfort = comfort
        self.pain = pain
    }

    /// Today's voice should rest instead of train.
    public var needsRest: Bool { pain || comfort <= 1 }
}

/// What to do after an attempt.
public enum Adjustment: String, Codable, Sendable, CaseIterable {
    /// The same exercise once more.
    case again
    /// One level down in the same skill.
    case easier
    /// One level up in the same skill.
    case harder
    /// On to the lesson's next step.
    case next
}

/// A lesson's shape. Each step's exercise is chosen when the step starts, from the plan as it is
/// then, so a pass earlier in the lesson already moves the next step on.
public enum LessonStep: Sendable, Equatable {
    case warmUp(String)
    case focus
    /// The top exercise of an earlier skill.
    case review(Skill)
}

public struct Lesson: Sendable, Equatable {
    public var focus: Skill
    public var steps: [LessonStep]
    /// A rest day: only gentle, unmeasured work.
    public var isRest: Bool
}

/// The person's plan: the library fitted to their voice and history. Rebuilt after every attempt
/// and every analysis, so targets and levels always follow the latest results.
///
/// - Each skill starts at the level the latest analyses place it (`Placement`); passes and misses in
///   lessons move it from there.
/// - Pitch bands start a step above (or below) the person's own average pitch and move toward the
///   goal's typical range one semitone per level.
/// - Timbre, flow and score goals start a little above the person's baseline.
/// - After two measured tries of an exercise, its goal rises to just above their recent median.
/// - Today's requests (`PlanRequests`) move the focus level, choose another skill, or rest.
public struct CoachPlan: Sendable {
    public let goal: VoiceGoal
    public let baseline: VoiceBaseline?
    public let attempts: [AttemptSummary]
    public let requests: PlanRequests
    /// Where the latest analyses place each skill.
    public let placement: [Skill: Int]
    public let progress: [Skill: SkillProgress]
    public let exercises: [Exercise]

    /// A goal at least this far below the pass line still counts as close.
    public static let closeMargin = 15.0
    /// A pass this far above the goal moves straight on to the next level.
    public static let leapMargin = 20.0
    /// How much harder the next goal is than the recent median.
    public static let stretch = 5.0
    /// How far above the baseline a first goal sits, and how much more per level.
    public static let firstStep = 8.0
    public static let perLevel = 5.0
    /// Width of a pitch band either side of its center, in semitones.
    public static let bandHalfWidth = 2.5

    public init(goal: VoiceGoal, baseline: VoiceBaseline?, attempts: [AttemptSummary], requests: PlanRequests = .none) {
        self.goal = goal
        self.baseline = baseline
        self.attempts = attempts
        self.requests = requests
        placement = Placement.levels(goal: goal, baseline: baseline)
        progress = Mastery.progress(attempts, placement: placement)
        let library = ExerciseLibrary.exercises(for: goal) { Self.band(goal: goal, baseline: baseline, level: $0) }
        exercises = library.map { Self.fitted($0, baseline: baseline, attempts: attempts) }
    }

    /// The skill a lesson works on: the one asked for today, or the path's next one.
    public var focus: Skill { requests.focus ?? Mastery.focus(progress) }

    /// The focus skill's level today: the earned one, moved by today's requests within the skill.
    public var focusLevel: Int {
        min(max((progress[focus]?.level ?? 1) + requests.levelShift, 1), ExerciseLibrary.levels(of: focus))
    }

    /// The plan with one more request of today's.
    public func with(_ request: PlanRequest) -> CoachPlan {
        var requests = requests
        requests.apply(request)
        return CoachPlan(goal: goal, baseline: baseline, attempts: attempts, requests: requests)
    }

    /// Whether a request changes today's lesson: its skill, its level, or rest. Asking for harder at
    /// the top level, easier at the first, or the skill already in focus changes nothing, and before
    /// the first analysis there is no lesson to change.
    public func isChanged(by request: PlanRequest) -> Bool {
        guard baseline != nil else { return false }
        let next = with(request)
        return next.focus != focus || next.focusLevel != focusLevel || next.requests.rest != requests.rest
    }

    public func exercise(_ id: String) -> Exercise? { exercises.first { $0.id == id } }

    /// The exercise for a skill at a level, clamped to the levels the skill has.
    public func exercise(_ skill: Skill, level: Int) -> Exercise {
        let ladder = exercises.filter { $0.skill == skill }.sorted { $0.level < $1.level }
        return ladder[min(max(level, 1), ladder.count) - 1]
    }

    /// About ten minutes: a warm-up, the focus skill twice (two passes move a level up), and the skill
    /// before it as a review. Lessons start once an analysis has set the starting point.
    public func lesson(checkIn: CheckInSummary?, day: Date = .now) -> Lesson {
        if checkIn?.needsRest == true || requests.rest { return Lesson(focus: focus, steps: [.warmUp("hum")], isRest: true) }
        let warmUps = ["straw", "lip_trill"]
        let dayNumber = Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: day) ?? 0
        var steps: [LessonStep] = [.warmUp(warmUps[dayNumber % warmUps.count]), .focus, .focus]
        if let review = Skill.allCases.prefix(while: { $0 != focus }).last { steps.append(.review(review)) }
        return Lesson(focus: focus, steps: steps, isRest: false)
    }

    /// The exercise a step stands for now.
    public func exercise(for step: LessonStep) -> Exercise {
        switch step {
        case .warmUp(let id): exercise(id)!
        case .focus: exercise(focus, level: focusLevel)
        case .review(let skill): exercise(skill, level: progress[skill]?.levels ?? 1)
        }
    }

    /// The rule-based reaction to an outcome. `tries` counts this step's attempts so far.
    public func adjustment(after outcome: Outcome, exercise: Exercise, value: Double?, tries: Int) -> Adjustment {
        switch outcome {
        case .passed:
            let leaps = exercise.skill != nil && (value ?? 0) >= exercise.goal.pass + Self.leapMargin
                && exercise.level < ExerciseLibrary.levels(of: exercise.skill!)
            return leaps ? .harder : .next
        case .close: return tries < 2 ? .again : .next
        case .missed:
            if exercise.level > 1, tries >= 2 { return .easier }
            return tries < 3 ? .again : .next
        case .unmeasured: return tries < 3 ? .again : .next
        }
    }

    /// The exercise an adjustment leads to, never outside the library. `next` returns nil: the
    /// lesson moves to its following step.
    public func apply(_ adjustment: Adjustment, to exercise: Exercise) -> Exercise? {
        guard let skill = exercise.skill else { return adjustment == .again ? self.exercise(exercise.id) : nil }
        switch adjustment {
        case .again: return self.exercise(exercise.id)
        case .easier: return self.exercise(skill, level: exercise.level - 1)
        case .harder: return self.exercise(skill, level: exercise.level + 1)
        case .next: return nil
        }
    }

    // MARK: Fitting

    /// The pitch band for a level: from the person's own average toward the goal's typical range.
    static func band(goal: VoiceGoal, baseline: VoiceBaseline?, level: Int) -> PitchTarget {
        let typical = PitchTarget.typicalBand(for: goal).range(at: 0)
        let typicalCenter = (typical.lowerBound * typical.upperBound).squareRoot()
        guard let own = baseline?.speakingF0Hz, own > 0 else { return .typicalBand(for: goal) }
        let up = goal == .feminine
        // Already at or past the typical center: the typical band is the target.
        guard up ? own < typicalCenter : own > typicalCenter else { return .typicalBand(for: goal) }
        let stepped = own * pow(2, (up ? 1 : -1) * Double(level) / 12)
        let center = up ? min(stepped, typicalCenter) : max(stepped, typicalCenter)
        let half = pow(2, bandHalfWidth / 12)
        return .band(low: center / half, high: center * half)
    }

    /// An exercise with its goal fitted to the person.
    static func fitted(_ exercise: Exercise, baseline: VoiceBaseline?, attempts: [AttemptSummary]) -> Exercise {
        guard exercise.tool != .timed else { return exercise }
        var fitted = exercise
        var pass = exercise.goal.pass
        let start: Double? = switch exercise.goal.measure {
        case .timbre: baseline?.timbre
        case .flow: baseline?.flow
        case .score: baseline?.score
        case .onTarget, .brightness, .completed: nil
        }
        if let start {
            let personal = start + firstStep + perLevel * Double(exercise.level - 1)
            pass = min(pass, max(personal, 30))
        }
        let recent = attempts.filter { $0.exerciseID == exercise.id }.sorted { $0.date > $1.date }.compactMap(\.value).prefix(3)
        if recent.count >= 2 {
            let median = recent.sorted()[recent.count / 2]
            pass = max(pass, min(median + stretch, 95))
        }
        fitted.goal = ExerciseGoal(measure: exercise.goal.measure, pass: pass.rounded(), close: max(pass - closeMargin, 0).rounded())
        return fitted
    }
}
