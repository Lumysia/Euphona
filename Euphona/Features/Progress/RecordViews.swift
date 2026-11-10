import EuphonaKit
import SwiftData
import SwiftUI

/// One analysis in a list: a tiny orb, time, length and score.
struct RecordRow: View {
    var record: AnalysisRecord
    /// Lists add their own disclosure indicator; custom containers ask for this one.
    var showsChevron = false

    var body: some View {
        HStack(spacing: 14) {
            VoiceOrb(balance: record.voiceBalance, halo: false)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.date, format: .dateTime.month().day().hour().minute())
                        .font(.body.weight(.medium))
                    if record.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel(Text(.dashboardPinned))
                    }
                }
                Text(verbatim: record.inputSeconds.rounded().clock)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: record.finalScore.formatted(decimals: 1))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Tokens.scoreColor(record.finalScore))
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, showsChevron ? 14 : 0)
        .padding(.vertical, showsChevron ? 12 : 4)
        .contentShape(.rect)
    }
}

extension AnalysisRecord {
    /// The analysis this one is compared with (`HistoryStore.previousAnalysis`).
    var previous: AnalysisRecord? {
        guard let modelContext else { return nil }
        return try? HistoryStore(context: modelContext).previousAnalysis(before: date, profile: scoreProfile)
    }
}

/// A past analysis, shown like a fresh result.
struct RecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorCenter.self) private var errors
    @Environment(\.dismiss) private var dismiss
    var record: AnalysisRecord
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let result = record.result {
                ResultView(content: ResultContent(record: record, result: result, previous: record.previous), animate: false)
            } else {
                ContentUnavailableView { Text(.historyDetailErrorTitle) }
            }
        }
        .navigationTitle(Text(record.date, format: .dateTime.month().day().hour().minute()))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ExportMenu(content: .analysis(record.persistentModelID), name: ExportFile.name(date: record.date),
                           recording: record.recordingFile)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { errors.attempt(.errorChangeFailed) { try HistoryStore(context: modelContext).setPinned(record, !record.pinned) } } label: {
                    Label { Text(record.pinned ? .dashboardUnpinRecord : .dashboardPinRecord) } icon: {
                        Image(systemName: record.pinned ? "pin.slash" : "pin")
                    }
                }
                .help(Text(record.pinned ? .dashboardUnpinRecord : .dashboardPinRecord))
                .sensoryFeedback(.selection, trigger: record.pinned)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label { Text(.dashboardDelete) } icon: { Image(systemName: "trash") }
                }
                .help(Text(.dashboardDelete))
                // Attached to the button so it pops out of it rather than rising from the bottom.
                .confirmationDialog(Text(.dashboardDeleteRecord), isPresented: $confirmingDelete) {
                    Button(role: .destructive) {
                        errors.attempt(.errorChangeFailed) { try HistoryStore(context: modelContext).delete(record) }
                        dismiss()
                    } label: { Text(.dashboardDelete) }
                }
            }
        }
    }
}
