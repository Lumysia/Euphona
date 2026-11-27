#if DEBUG
import Foundation
import EuphonaKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Screenshot data for development builds: launch with `-demo_audio <folder of WAVs>` and each file
/// is analyzed by the engine and saved as a record on a past day. Pass `-demo_screen <name>` to open a screen.
enum DemoData {
    static var audioFolder: URL? { UserDefaults.standard.string(forKey: "demo_audio").map { URL(filePath: $0) } }
    static var screen: String? { UserDefaults.standard.string(forKey: "demo_screen") }
    /// A message the coach conversation sends once when it opens (`-demo_message <text>`).
    static var message: String? { UserDefaults.standard.string(forKey: "demo_message") }
    /// A folder every export is written to after seeding (`-demo_export <folder>`), to check the files.
    static var exportFolder: URL? { UserDefaults.standard.string(forKey: "demo_export").map { URL(filePath: $0) } }

    @MainActor static func exportIfRequested(context: ModelContext, tint: Color) {
        guard let folder = exportFolder,
              let latest = try? context.fetch(FetchDescriptor<AnalysisRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])).first
        else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for content in [ExportFile.Content.analysis(latest.persistentModelID), .history] {
            for format in ExportFile.Format.allCases {
                let file = ExportFile(content: content, format: format, name: content == .history ? "history" : "analysis",
                                      container: context.container, tint: tint)
                try? file.data().write(to: folder.appending(path: file.name).appendingPathExtension(for: format.type))
            }
        }
    }

    @MainActor static func seedIfRequested(context: ModelContext, engine: VoiceEngine, settings: AppSettings) async {
        guard let folder = audioFolder, (try? context.fetchCount(FetchDescriptor<AnalysisRecord>())) == 0 else { return }
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let analyzer = try? await engine.analyzer(for: settings.analyzer) else { return }
        let store = HistoryStore(context: context)
        let calendar = Calendar.current
        var added: [AnalysisRecord] = []
        for file in files {
            guard let audio = try? await AudioFileReader.read(file),
                  let result = try? await offMain({ try analyzer.analyze(audio, profile: .feminization) }),
                  let record = try? store.addAnalysis(result, audio: try? AudioEncoder.aac(audio),
                                                      audioFormat: AudioEncoder.fileExtension) else { continue }
            added.append(record)
        }
        // Dated in order of score, with steps between the lowest and highest clip, so the demo history
        // climbs over several weeks the way practice should. The newest analysis is from earlier today.
        let sorted = added.sorted { $0.finalScore < $1.finalScore }
        var climb = sorted
        if let low = sorted.first, let high = sorted.last, sorted.count > 1 {
            let steps = (1...climbSteps).compactMap { step(from: low, to: high, at: Double($0) / Double(climbSteps + 1)) }
            for step in steps { context.insert(step) }
            climb = [low] + steps + sorted.dropFirst()
        }
        let newest = Date.now.addingTimeInterval(-2 * 3600)
        for (index, record) in climb.enumerated() {
            let daysAgo = (climb.count - 1 - index) * 3
            record.date = calendar.date(byAdding: .day, value: -daysAgo, to: newest)!.addingTimeInterval(Double(index % 4) * 2700)
        }
        try? context.save()
        // A practice streak of the last two weeks, with a few missed days before it.
        for daysAgo in 0..<40 where daysAgo < 14 || daysAgo % 3 != 1 {
            try? store.recordOpenedDay(calendar.date(byAdding: .day, value: -daysAgo, to: .now)!)
        }
        // A short conversation with the coach, ending in a quick reply.
        let hour = { (hours: Double) in Date.now.addingTimeInterval(-hours * 3600) }
        try? store.addNote(String(localized: .coachReviewPassed("72 %", "60 %")), exerciseID: "pitch_hold", date: hour(26))
        try? store.addNote("Can we spend more time on resonance? Pitch feels fine now.", fromLearner: true, date: hour(3))
        try? store.addNote("Of course. Today’s lesson works on resonance, starting from the bright “ee” you already reach.", date: hour(3))
        let records = (try? context.fetch(FetchDescriptor<AnalysisRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        try? QuickReply.tooEasy.send(store: store, plan: CoachPlan(goal: settings.voiceGoal, records: records, attempts: [], requests: []))
    }

    private static let climbSteps = 12

    /// A summary-only analysis part of the way (`t`, 0...1) from `low` to `high`, eased so early
    /// practice gains the most, with a small wobble so the line looks like real practice. It has no
    /// stored result, so rescoring at launch keeps its numbers.
    private static func step(from low: AnalysisRecord, to high: AnalysisRecord, at t: Double) -> AnalysisRecord? {
        guard let base = low.result else { return nil }
        let eased = min(1, max(0, 1 - pow(1 - t, 1.6) + sin(t * 23) * 0.035))
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * eased }
        let record = AnalysisRecord(result: base, audio: nil, audioFormat: nil)
        record.resultJSON = nil
        record.finalScore = mix(low.finalScore, high.finalScore)
        record.timbreScore = mix(low.timbreScore, high.timbreScore)
        record.flowScore = mix(low.flowScore, high.flowScore)
        record.easeScore = mix(low.easeScore, high.easeScore)
        if let a = low.speakingF0Hz, let b = high.speakingF0Hz { record.speakingF0Hz = mix(a, b) }
        if let a = low.f0VariationHz, let b = high.f0VariationHz { record.f0VariationHz = mix(a, b) }
        return record
    }
}

/// A screen opened directly for screenshots.
struct DemoScreen: Identifiable {
    let name: String
    var id: String { name }

    @MainActor @ViewBuilder var view: some View {
        // A lesson brings its own navigation stack: "lesson" starts at the check-in, "lesson-intro" after it.
        if name.hasPrefix("lesson") {
            LessonView(session: LessonSession(goal: .feminine, analyses: [], attempts: [], requests: .none,
                                              checkIn: name == "lesson" ? nil : CheckInSummary(comfort: 4, pain: false)))
        } else {
            screens
        }
    }

    @MainActor @ViewBuilder private var screens: some View {
        NavigationStack {
            Group {
                switch name {
                case "result", "rules", "reveal", "streak": DemoRecordScreen(name: name)
                case "pitch": PitchView()
                case "timbre": TimbreView()
                case "resonance": ResonanceView()
                case "spectrum": SpectrumView()
                case "piano": PianoView()
                case "quality": VoiceQualityView()
                case "chat": CoachChatView()
                case "about": AboutView()
                case "feedback": FeedbackView()
                case "history": HistoryListView()
                case "controls":
                    // Both states of the record button, which needs a microphone to see otherwise.
                    VStack(spacing: 40) {
                        CaptureButton(isRecording: false, isEnabled: true) {}
                        CaptureButton(isRecording: true, isEnabled: true) {}
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { AmbientBackground(balance: 0.6) }
                default: EmptyView()
                }
            }
            .appRoutes()
        }
    }
}

private struct DemoRecordScreen: View {
    var name: String
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]

    var body: some View {
        if let record = records.first(where: { $0.finalScore > 50 }) ?? records.first, let result = record.result {
            switch name {
            case "rules": ScoreRulesView(result: result, previousScore: records.dropFirst().first?.finalScore, previous: nil)
            case "reveal": ResultReveal(content: ResultContent(record: record, result: result, previous: records.dropFirst().first), streak: nil)
            case "streak":
                StreakCelebration(streak: Streak(activity: [Date.now.addingTimeInterval(-86_400), Date.now.addingTimeInterval(-2 * 86_400), .now])) {}
            default: RecordDetailView(record: record)
            }
        }
    }
}
#endif
