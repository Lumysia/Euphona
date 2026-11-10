import Foundation
import FoundationModels
import EuphonaKit
import Synchronization

/// The conversation with the coach. Every message starts a fresh session that sees today's data and
/// the recent conversation, so nothing goes stale and the on-device context never fills up. The
/// model answers briefly and may suggest a change to today's plan through `SuggestChange`; the model
/// never changes the plan itself: the suggestion shows as a quick reply under its answer, and only
/// the learner's tap applies it. A small model reads a joke or a stray word as a request too easily.
enum CoachChat {
    /// Messages of the conversation the model sees with each new message.
    static let contextMessages = 8

    struct Answer {
        var text: String
        /// The change the model suggests, for the learner to confirm.
        var suggestion: PlanRequest?
    }

    /// The coach's answer, or nil when the model couldn't answer.
    static func answer(_ message: String, plan: CoachPlan, snapshot: LanguageCoach.Snapshot, choice: CoachModelChoice) async -> Answer? {
        let calls = CallCounter()
        let suggestion = Suggestion(plan)
        let tools = LanguageCoach.lookUps(snapshot, calls: calls) + [SuggestChange(suggestion: suggestion, calls: calls)]
        let prompt = """
        Recent conversation:
        \(snapshot.notes)

        Today's plan:
        \(snapshot.skillProgress)

        The learner now says: \(message)
        """
        // The first answer after launch can fail while the model loads; one more try usually works.
        for _ in 0..<2 {
            guard let session = LanguageCoach.session(choice, tools: tools, instructions: instructions) else { return nil }
            calls.reset()
            suggestion.reset()
            if let text = try? await session.respond(to: prompt, options: LanguageCoach.options).content
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return Answer(text: text, suggestion: suggestion.request)
            }
        }
        return nil
    }

    private static var instructions: String {
        """
        You are the voice coach in Euphona, an app for people training their voice toward a more \
        feminine or more masculine sound, often trans and gender-diverse people. The learner is talking \
        to you between lessons. Answer what they actually said in one to three short, warm, plain \
        sentences; small talk, jokes and anything unclear get a friendly reply and nothing else. Only \
        when they clearly ask to change their training (easier, harder, rest, practise a skill, or back \
        to the plan), or say their voice is tired or hurts, call suggestChange once: it puts a button \
        under your answer, so ask whether they want it and never say it is done. The skills are: \
        pitch (speaking pitch), resonance (the brightness of the voice), intonation (melody and flow) \
        and carryOver (using the voice in everyday speech). Use only Euphona's own lessons and tools, \
        never invent exercises, never diagnose or give medical advice, and never comment on the \
        learner's identity. If they mention pain, tell them to rest and suggest rest. You may call tools at most \
        \(LanguageCoach.toolCallLimit) times in total. Write in \(LanguageCoach.languageName).
        """
    }
}

/// Suggests a change to today's plan, the way a quick reply would make it; the learner confirms.
private struct SuggestChange: Tool {
    let name = "suggestChange"
    let description = "Suggests a change to today's training (easier, harder, rest, focus on one skill, or back to the plan) as a button the learner can tap."
    let suggestion: Suggestion
    let calls: CallCounter

    @Generable
    struct Arguments {
        @Guide(description: "The change the learner asked for.")
        var change: Change
        @Guide(description: "For focus, the skill to practise today; otherwise ignored.", .anyOf(Skill.allCases.map(\.rawValue)))
        var skill: String
    }

    @Generable
    enum Change {
        case easier, harder, rest, focus, backToPlan
    }

    func call(arguments: Arguments) async throws -> String {
        guard calls.next() <= LanguageCoach.toolCallLimit else { return "No more suggestions now." }
        let request: PlanRequest = switch arguments.change {
        case .easier: PlanRequest(.easier)
        case .harder: PlanRequest(.harder)
        case .rest: PlanRequest(.rest)
        case .focus: PlanRequest(.focus, skill: Skill(rawValue: arguments.skill) ?? .pitch)
        case .backToPlan: PlanRequest(.reset)
        }
        guard suggestion.offer(request) else {
            return "Nothing to suggest: today's lesson already works that way (no level beyond the top or below the first)."
        }
        return "Suggested. A button under your answer lets the learner confirm; ask them, and don't say it is done."
    }
}

/// The one change an answer suggests, if it would change today's lesson.
private nonisolated final class Suggestion: Sendable {
    private let plan: CoachPlan
    private let state = Mutex<PlanRequest?>(nil)

    init(_ plan: CoachPlan) { self.plan = plan }

    /// Keeps `request` when it would change the lesson; returns whether it did.
    func offer(_ request: PlanRequest) -> Bool {
        guard plan.isChanged(by: request) else { return false }
        state.withLock { $0 = request }
        return true
    }

    func reset() { state.withLock { $0 = nil } }
    var request: PlanRequest? { state.withLock { $0 } }
}
