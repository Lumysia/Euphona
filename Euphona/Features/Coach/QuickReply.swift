import EuphonaKit
import SwiftUI

/// A one-tap message to the coach. It works the same with or without a language model: it stores
/// what the learner said, the plan change, and the coach's written answer in the conversation. A
/// reply that can't change today's lesson (harder at the top level) is answered but not stored.
enum QuickReply: Hashable {
    case tooEasy, tooHard, tired, focus(Skill), backToPlan

    /// The replies offered on the Coach tab and in the conversation.
    static func all(_ requests: PlanRequests) -> [QuickReply] {
        var replies: [QuickReply] = [.tooEasy, .tooHard, .tired]
        if requests != .none { replies.append(.backToPlan) }
        return replies
    }

    /// The replies that make sense during a lesson.
    static func inLesson(_ lesson: Lesson) -> [QuickReply] {
        lesson.isRest ? [] : [.tooEasy, .tooHard, .tired]
    }

    /// The reply that makes `request`: how a suggestion from the coach is confirmed.
    init(_ request: PlanRequest) {
        self = switch request.kind {
        case .harder: .tooEasy
        case .easier: .tooHard
        case .rest: .tired
        case .focus: .focus(request.skill ?? .pitch)
        case .reset: .backToPlan
        }
    }

    var request: PlanRequest {
        switch self {
        case .tooEasy: PlanRequest(.harder)
        case .tooHard: PlanRequest(.easier)
        case .tired: PlanRequest(.rest)
        case .focus(let skill): PlanRequest(.focus, skill: skill)
        case .backToPlan: PlanRequest(.reset)
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .tooEasy: .coachTellTooEasy
        case .tooHard: .coachTellTooHard
        case .tired: .coachTellTired
        case .focus(let skill): .coachTellFocus(String(localized: skill.title))
        case .backToPlan: .coachTellBackToPlan
        }
    }

    var symbol: String {
        switch self {
        case .tooEasy: "arrow.up.right"
        case .tooHard: "arrow.down.right"
        case .tired: "leaf"
        case .focus(let skill): skill.symbol
        case .backToPlan: "arrow.uturn.backward"
        }
    }

    /// What the coach answers: the change as `changed` has it, or why nothing changed.
    func answer(_ changed: CoachPlan?, from plan: CoachPlan) -> LocalizedStringResource {
        let skill = String(localized: plan.focus.title)
        guard let changed else {
            return switch self {
            case .tooEasy: .coachAnswerNoHarder(skill)
            case .tooHard: .coachAnswerNoEasier(skill)
            default: .coachAnswerNoChange
            }
        }
        return switch self {
        case .tooEasy: .coachAnswerHarder(skill, changed.focusLevel)
        case .tooHard: .coachAnswerEasier(skill, changed.focusLevel)
        case .tired: .coachAnswerRest
        case .focus(let skill): .coachAnswerFocus(String(localized: skill.title))
        case .backToPlan: .coachAnswerBackToPlan
        }
    }

    /// Says it to the coach; returns whether today's plan changed.
    @discardableResult
    func send(store: HistoryStore, plan: CoachPlan) throws -> Bool {
        let changed = plan.isChanged(by: request) ? plan.with(request) : nil
        try store.addNote(String(localized: label), fromLearner: true)
        if changed != nil { try store.addRequest(request) }
        try store.addNote(String(localized: answer(changed, from: plan)))
        return changed != nil
    }
}

/// The quick replies as a row of glass buttons, with a menu to choose a skill to practise.
struct QuickReplyBar: View {
    var requests: PlanRequests
    var send: (QuickReply) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(QuickReply.all(requests), id: \.self) { reply in
                        Button { send(reply) } label: { Label { Text(reply.label) } icon: { Image(systemName: reply.symbol) } }
                    }
                    Menu {
                        ForEach(Skill.allCases, id: \.self) { skill in
                            Button { send(.focus(skill)) } label: { Label { Text(skill.title) } icon: { Image(systemName: skill.symbol) } }
                        }
                    } label: {
                        Label { Text(.coachTellPractise) } icon: { Image(systemName: "scope") }
                    }
                }
                .buttonStyle(.glass)
                .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}

extension LanguageCoach.Snapshot {
    /// What the language model's tools can read, written plainly. `attempts`, `records` and `notes`
    /// newest first.
    @MainActor
    init(plan: CoachPlan, attempts: [CoachAttempt], records: [AnalysisRecord], notes: [CoachNote]) {
        let recent = attempts.prefix(12).compactMap { attempt -> String? in
            guard let exercise = plan.exercise(attempt.exerciseID) else { return nil }
            let value = attempt.value.map(exercise.describe) ?? "-"
            return "\(attempt.date.formatted(date: .abbreviated, time: .shortened)): \(exercise.title), \(value), \(attempt.outcome.rawValue)"
        }
        var skills = Skill.allCases.map { skill in
            let p = plan.progress[skill]!
            return "\(skill.rawValue) (\(String(localized: skill.title))): level \(p.level) of \(p.levels)\(p.isComplete ? ", complete" : "")"
        }
        skills.append("Today's focus: \(plan.focus.rawValue), level \(plan.focusLevel)\(plan.requests.rest ? ", resting today" : "")")
        let latest = records.first.map { record in
            "\(record.date.formatted(date: .abbreviated, time: .omitted)): overall \(record.finalScore.formatted(decimals: 0)), "
                + "timbre \(record.timbreScore.formatted(decimals: 0)), flow \(record.flowScore.formatted(decimals: 0)), ease \(record.easeScore.formatted(decimals: 0)), "
                + "speaking pitch \(record.speakingF0Hz.map { $0.hertz() } ?? "-")"
        } ?? "No analysis yet."
        let conversation = notes.prefix(8).reversed().map { "\($0.fromLearner ? "Learner" : "Coach"): \($0.text)" }
        self.init(recentAttempts: recent.isEmpty ? "No attempts yet." : recent.joined(separator: "\n"),
                  skillProgress: skills.joined(separator: "\n"), latestAnalysis: latest,
                  notes: conversation.isEmpty ? "Nothing yet." : conversation.joined(separator: "\n"))
    }
}
