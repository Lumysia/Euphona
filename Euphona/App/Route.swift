import EuphonaKit
import SwiftData
import SwiftUI

/// Every place a navigation stack can push to.
///
/// Links carry a `Route` value (`NavigationLink(value:)`) and each stack maps values to screens with
/// `appRoutes()`. A pushed screen then depends only on the value, never on which link view SwiftUI
/// matched: with destination-closure links, a list refreshing under the finger (a save or an iCloud
/// change) could open a different link's screen.
enum Route: Hashable {
    case record(PersistentIdentifier)
    /// The scoring rules of a saved analysis, compared with the analysis before it.
    case rules(record: PersistentIdentifier)
    case metric(InsightMetric)
    case activity
    case history
    case practice(PracticeTool)
    case advancedSettings
    case about
    case feedback
    case coachChat
}

enum PracticeTool: Hashable {
    case pitch, timbre, resonance, spectrum, piano, voiceQuality
}

extension View {
    /// Registers the screens for every `Route`. Apply once at the root of each `NavigationStack`.
    func appRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}

private struct RouteDestination: View {
    var route: Route

    var body: some View {
        switch route {
        case .record(let id):
            SavedRecord(id: id) { RecordDetailView(record: $0) }
        case .rules(let id):
            SavedRecord(id: id) { record in
                if let result = record.result {
                    let previous = record.previous
                    ScoreRulesView(result: result, previousScore: previous?.finalScore, previous: previous.map(PreviousMetrics.init))
                }
            }
        case .metric(let metric):
            MetricDetailView(metric: metric)
        case .activity:
            ActivityView()
        case .history:
            HistoryListView()
        case .practice(.pitch):
            PitchView()
        case .practice(.timbre):
            TimbreView()
        case .practice(.resonance):
            ResonanceView()
        case .practice(.spectrum):
            SpectrumView()
        case .practice(.piano):
            PianoView()
        case .practice(.voiceQuality):
            VoiceQualityView()
        case .advancedSettings:
            AdvancedSettings()
        case .coachChat:
            CoachChatView()
        case .about:
            AboutView()
        case .feedback:
            FeedbackView()
        }
    }
}

/// Looks a record up by its ID, so a pushed screen survives refreshes and shows a notice once the record
/// is deleted (on this device or another).
private struct SavedRecord<Content: View>: View {
    var id: PersistentIdentifier
    @ViewBuilder var content: (AnalysisRecord) -> Content
    @Query private var matches: [AnalysisRecord]

    init(id: PersistentIdentifier, @ViewBuilder content: @escaping (AnalysisRecord) -> Content) {
        self.id = id
        self.content = content
        _matches = Query(filter: #Predicate<AnalysisRecord> { $0.persistentModelID == id })
    }

    var body: some View {
        if let record = matches.first {
            content(record)
        } else {
            ContentUnavailableView { Text(.historyDetailErrorTitle) }
        }
    }
}
