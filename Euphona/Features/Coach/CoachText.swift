import EuphonaKit
import SwiftUI

extension Exercise {
    var title: String { localized(key: "coach_ex_\(key)_title") }
    var steps: String { localized(key: "coach_ex_\(key)_steps") }
    var why: String { localized(key: "coach_ex_\(key)_why") }
    var tip: String { localized(key: "coach_ex_\(key)_tip") }

    var symbol: String {
        switch tool {
        case .timed: "wind"
        case .pitch: "waveform.path"
        case .timbre: "person.wave.2"
        case .resonance: "circle.hexagongrid"
        case .reading: "text.book.closed"
        case .conversation: "bubble.left.and.text.bubble.right"
        }
    }

    /// A goal value written for people: a share as a percent, a score as a number.
    func formatted(_ value: Double) -> String {
        switch goal.measure {
        case .onTarget, .completed: value.percent(decimals: 0)
        default: value.formatted(decimals: 0)
        }
    }

    /// The goal in a few words: its time for a warm-up, its target otherwise.
    var goalSummary: String {
        tool == .timed ? Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)) : describe(goal.pass)
    }

    /// "72 % in range", "timbre 64", …
    func describe(_ value: Double) -> String {
        let text = formatted(value)
        return switch goal.measure {
        case .onTarget: String(localized: .coachValueOnTarget(text))
        case .timbre: String(localized: .coachValueTimbre(text))
        case .brightness: String(localized: .coachValueBrightness(text))
        case .flow: String(localized: .coachValueFlow(text))
        case .score: String(localized: .coachValueScore(text))
        case .completed: String(localized: .coachValueCompleted(text))
        }
    }
}

extension Skill {
    var title: LocalizedStringResource {
        switch self {
        case .pitch: .coachSkillPitch
        case .resonance: .coachSkillResonance
        case .intonation: .coachSkillIntonation
        case .carryOver: .coachSkillCarryOver
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .pitch: .coachSkillPitchSummary
        case .resonance: .coachSkillResonanceSummary
        case .intonation: .coachSkillIntonationSummary
        case .carryOver: .coachSkillCarryOverSummary
        }
    }

    var symbol: String {
        switch self {
        case .pitch: "waveform.path"
        case .resonance: "circle.hexagongrid"
        case .intonation: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .carryOver: "bubble.left.and.bubble.right"
        }
    }
}

extension Outcome {
    var title: LocalizedStringResource {
        switch self {
        case .passed: .coachOutcomePassed
        case .close: .coachOutcomeClose
        case .missed: .coachOutcomeMissed
        case .unmeasured: .coachOutcomeUnmeasured
        }
    }

    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .close: "circle.lefthalf.filled"
        case .missed: "arrow.counterclockwise.circle.fill"
        case .unmeasured: "ear.trianglebadge.exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .passed: Tokens.success
        case .close: Tokens.scoreMid
        case .missed: Tokens.warning
        case .unmeasured: .secondary
        }
    }
}

extension Adjustment {
    var title: LocalizedStringResource {
        switch self {
        case .again: .coachActionAgain
        case .easier: .coachActionEasier
        case .harder: .coachActionHarder
        case .next: .coachActionNext
        }
    }
}

/// Prompts for speaking freely, numbered in the catalog as `coach_talk_prompt_<n>`.
enum TalkPrompts {
    static let count = 8

    static func prompt(_ index: Int) -> String {
        localized(key: "coach_talk_prompt_\(index % count + 1)")
    }
}
