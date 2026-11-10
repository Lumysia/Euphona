import EuphonaKit
import SwiftData
import SwiftUI

/// Every analysis: pinned first, then by day, newest first. Swipe or open the context menu to pin,
/// share or delete; the toolbar shares the whole list as an image or a PDF.
struct HistoryListView: View {
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]

    var body: some View {
        List {
            let pinned = records.filter(\.pinned)
            if !pinned.isEmpty {
                Section { rows(pinned) } header: { Text(.dashboardPinnedSection) }
            }
            ForEach(days(records.filter { !$0.pinned }), id: \.day) { group in
                Section { rows(group.records) } header: {
                    Text(group.day, format: .dateTime.year().month(.wide).day().weekday(.wide))
                }
            }
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView { Label { Text(.dashboardNoAnalysis) } icon: { Image(systemName: "waveform") } }
            }
        }
        .navigationTitle(Text(.dashboardAnalysisHistory))
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ExportMenu(content: .history, name: ExportFile.name("Euphona \(String(localized: .dashboardAnalysisHistory))", date: .now))
                }
            }
        }
    }

    private func rows(_ records: [AnalysisRecord]) -> some View {
        ForEach(records) { record in
            NavigationLink(value: Route.record(record.persistentModelID)) { RecordRow(record: record) }
                .recordActions(record)
        }
    }

    private func days(_ records: [AnalysisRecord]) -> [(day: Date, records: [AnalysisRecord])] {
        Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }
}
