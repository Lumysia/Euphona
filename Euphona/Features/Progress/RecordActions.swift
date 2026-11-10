import EuphonaKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A saved recording as a shareable audio file, named after its date.
struct RecordingFile: Transferable {
    var data: Data
    var date: Date

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .mpeg4Audio) { $0.data }
            .suggestedFileName { ExportFile.name(date: $0.date) }
    }
}

extension AnalysisRecord {
    var recordingFile: RecordingFile? { audio.map { RecordingFile(data: $0, date: date) } }

    /// Share as an image, a PDF or the recording.
    var exportItems: ExportItems {
        ExportItems(content: .analysis(persistentModelID), name: ExportFile.name(date: date), recording: recordingFile)
    }
}

/// Pin, share and delete for one analysis, the same in every list: a context menu, and on a list
/// row also swipe actions.
private struct RecordActions: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorCenter.self) private var errors
    var record: AnalysisRecord
    var swipes: Bool

    func body(content: Content) -> some View {
        content
            .contextMenu {
                pinButton
                Menu { record.exportItems } label: {
                    Label { Text(.shareTitle) } icon: { Image(systemName: "square.and.arrow.up") }
                }
                Divider()
                deleteButton
            }
            .swipeActions(edge: .trailing) {
                if swipes {
                    deleteButton
                    pinButton.tint(.orange)
                }
            }
    }

    private var pinButton: some View {
        Button { errors.attempt(.errorChangeFailed) { try HistoryStore(context: modelContext).setPinned(record, !record.pinned) } } label: {
            Label { Text(record.pinned ? .dashboardUnpinRecord : .dashboardPinRecord) } icon: {
                Image(systemName: record.pinned ? "pin.slash" : "pin")
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { errors.attempt(.errorChangeFailed) { try HistoryStore(context: modelContext).delete(record) } } label: {
            Label { Text(.dashboardDelete) } icon: { Image(systemName: "trash") }
        }
    }
}

extension View {
    func recordActions(_ record: AnalysisRecord, swipes: Bool = true) -> some View {
        modifier(RecordActions(record: record, swipes: swipes))
    }
}
