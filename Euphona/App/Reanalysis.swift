import EuphonaKit
import Foundation
import SwiftData

/// Analyzes saved recordings again when the models changed (`EuphonaAnalyzer.modelVersion`), so
/// every analysis in the history is scored by the same models and comparisons stay fair. Runs at
/// launch, one recording at a time off the main actor; an analysis without its recording keeps the
/// scores it had.
enum Reanalysis {
    @MainActor
    static func run(context: ModelContext, engine: VoiceEngine, settings: AnalyzerSettings) async {
        let records = (try? context.fetch(FetchDescriptor<AnalysisRecord>())) ?? []
        let outdated = records.filter { $0.audio != nil && $0.result?.modelVersion != EuphonaAnalyzer.modelVersion }
        guard !outdated.isEmpty, let analyzer = try? await engine.analyzer(for: settings) else { return }
        for record in outdated {
            guard let data = record.audio, let audio = await decode(data, format: record.audioFormat) else { continue }
            let profile = record.scoreProfile
            guard let result = try? await offMain({ try analyzer.analyze(audio, profile: profile) }) else { continue }
            // The record may have been deleted meanwhile.
            guard !record.isDeleted, record.modelContext != nil else { continue }
            record.refresh(from: result)
            try? context.save()
        }
    }

    private static func decode(_ data: Data, format: String?) async -> PCMBuffer? {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(format ?? AudioEncoder.fileExtension)")
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        return try? await AudioFileReader.read(url)
    }
}
