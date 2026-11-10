import Foundation
import FoundationModels
import EuphonaKit
import Synchronization

/// Reviews attempts with Apple's language models, on the device or in Private Cloud Compute. It can
/// look things up through read-only tools (at most `toolCallLimit` calls), says what it thinks in the
/// app's language, and proposes the next step; `WrittenCoach.bounded` keeps that step within what
/// the outcome allows, and the planner turns it into an exercise from the library. Any failure falls
/// back to the written coach.
enum LanguageCoach {
    nonisolated static let toolCallLimit = 5

    /// Whether the chosen model can review right now, in the app's language.
    static func isAvailable(_ choice: CoachModelChoice) -> Bool {
        guard SystemLanguageModel.default.supportsLocale() else { return false }
        switch choice {
        case .onDevice: return SystemLanguageModel.default.isAvailable
        case .privateCloud:
            guard #available(iOS 27, macOS 27, *) else { return false }
            return PrivateCloudComputeLanguageModel().isAvailable
        case .off: return false
        }
    }

    /// What the tools can tell the model, gathered on the main actor before the session starts.
    struct Snapshot: Sendable {
        var recentAttempts: String
        var skillProgress: String
        var latestAnalysis: String
        var notes: String
    }

    static func review(_ context: ReviewContext, snapshot: Snapshot, choice: CoachModelChoice) async -> CoachReview? {
        guard let session = session(choice, tools: lookUps(snapshot, calls: CallCounter()), instructions: instructions) else { return nil }
        do {
            let reply = try await session.respond(to: prompt(context), generating: Reply.self, options: options).content
            let message = reply.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return nil }
            return CoachReview(message: message, adjustment: WrittenCoach.bounded(reply.next.adjustment, context), byModel: true)
        } catch {
            return nil
        }
    }

    /// A session with the chosen model, or nil when it can't be used.
    static func session(_ choice: CoachModelChoice, tools: [any Tool], instructions: String) -> LanguageModelSession? {
        guard isAvailable(choice) else { return nil }
        switch choice {
        case .onDevice: return LanguageModelSession(tools: tools, instructions: instructions)
        case .privateCloud:
            guard #available(iOS 27, macOS 27, *) else { return nil }
            return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), tools: tools, instructions: instructions)
        case .off: return nil
        }
    }

    /// The read-only tools, all reading one snapshot.
    static func lookUps(_ snapshot: Snapshot, calls: CallCounter) -> [any Tool] {
        [
            LookUp(name: "recentAttempts", description: "The learner's latest coach exercise attempts and how they went.", text: snapshot.recentAttempts, calls: calls),
            LookUp(name: "skillProgress", description: "Level and progress on each skill of the path, and today's focus.", text: snapshot.skillProgress, calls: calls),
            LookUp(name: "latestAnalysis", description: "The learner's latest full voice analysis.", text: snapshot.latestAnalysis, calls: calls),
            LookUp(name: "conversation", description: "What the learner and the coach said to each other recently.", text: snapshot.notes, calls: calls),
        ]
    }

    static let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: 220)

    static var languageName: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    private static var instructions: String {
        """
        You are the voice coach in Euphona, an app for people training their voice toward a more \
        feminine or more masculine sound, often trans and gender-diverse people. You have just watched \
        one attempt at an exercise from Euphona's library. Write one to three short sentences to the \
        learner: what went well or what the measurement shows, and one concrete thing to do next, using \
        only the exercise's own instructions and tip. Be warm, specific and plain. Never diagnose, never \
        give medical advice, never invent an exercise, and never comment on the learner's identity. If \
        the learner mentions pain, tell them to rest. You may call tools at most \
        \(toolCallLimit) times in total, and only when they help. Write in \(languageName).
        """
    }

    private static func prompt(_ context: ReviewContext) -> String {
        let exercise = context.exercise
        let measured = context.value.map(exercise.describe) ?? "nothing measurable"
        return """
        Voice goal: \(context.goal == .feminine ? "more feminine" : "more masculine").
        Exercise: \(exercise.title).
        Instructions: \(exercise.steps)
        Tip: \(exercise.tip)
        Goal: \(exercise.describe(exercise.goal.pass)).
        Measured: \(measured). Outcome: \(context.outcome.rawValue). Attempt \(context.tries) at this step.
        Choose the next step: again, easier, harder or next.
        """
    }
}

@Generable
private struct Reply {
    @Guide(description: "One to three short sentences to the learner.")
    var message: String
    @Guide(description: "What the learner should do next.")
    var next: Next
}

@Generable
private enum Next {
    case again, easier, harder, next

    var adjustment: Adjustment {
        switch self {
        case .again: .again
        case .easier: .easier
        case .harder: .harder
        case .next: .next
        }
    }
}

/// Tool calls made toward one answer, shared by the session's tools.
nonisolated final class CallCounter: Sendable {
    private let count = Mutex(0)

    func next() -> Int { count.withLock { $0 += 1; return $0 } }
    func reset() { count.withLock { $0 = 0 } }
}

/// A read-only tool returning prepared text, counting calls toward the session's limit.
private struct LookUp: Tool {
    let name: String
    let description: String
    let text: String
    let calls: CallCounter

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        guard calls.next() <= LanguageCoach.toolCallLimit else { throw LimitReached() }
        return text
    }

    struct LimitReached: Error {}
}
