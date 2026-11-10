import Observation
import EuphonaKit

/// Owns the shared analyzer and rebuilds it when the analyzer settings change.
/// Streams keep their own analyzer alive, so a rebuild never pulls one out from under them.
@MainActor @Observable
final class VoiceEngine {
    @ObservationIgnored private var current: (settings: AnalyzerSettings, task: Task<EuphonaAnalyzer, Error>)?

    func analyzer(for settings: AnalyzerSettings) async throws -> EuphonaAnalyzer {
        if let current, current.settings == settings { return try await current.task.value }
        let task = Task.detached(priority: .userInitiated) { try EuphonaAnalyzer(settings: settings) }
        current = (settings, task)
        return try await task.value
    }
}

/// Runs blocking analysis work off the main actor.
@concurrent
func offMain<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
    try work()
}
