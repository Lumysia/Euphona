import EuphonaKit
import ImageIO
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// An analysis or the list of analyses as an image or a PDF. It holds only what finds the records,
/// and draws them when the share sheet or the save panel asks for the file, so offering it costs
/// nothing.
struct ExportFile: Transferable {
    enum Content: Hashable, Sendable {
        case analysis(PersistentIdentifier)
        /// Every analysis, newest first.
        case history
    }

    enum Format: Sendable, CaseIterable {
        case image, pdf

        var type: UTType { self == .image ? .png : .pdf }
    }

    var content: Content
    var format: Format
    var name: String
    var container: ModelContainer
    var tint: Color

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { try await $0.data() }
            .exportingCondition { $0.format == .image }
            .suggestedFileName(\.name)
        DataRepresentation(exportedContentType: .pdf) { try await $0.data() }
            .exportingCondition { $0.format == .pdf }
            .suggestedFileName(\.name)
    }

    @MainActor func data() throws -> Data {
        let context = container.mainContext
        let analyses: [ReportAnalysis] = switch content {
        case .analysis(let id): [(context.model(for: id) as? AnalysisRecord).map { ReportAnalysis($0, detailed: true) }].compactMap { $0 }
        case .history: try context.fetch(FetchDescriptor<AnalysisRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            .map { ReportAnalysis($0, detailed: false) }
        }
        guard !analyses.isEmpty, let data = ReportRenderer(tint: tint).render(pages(analyses)) else { throw ExportFailed() }
        return data
    }

    /// The pages to draw: one per analysis report; the table split across pages for a PDF and in one
    /// long image otherwise.
    @MainActor private func pages(_ analyses: [ReportAnalysis]) -> ReportRenderer.Pages {
        switch content {
        case .analysis:
            let analysis = analyses[0]
            let details = [analysis.date.formatted(date: .long, time: .shortened), analysis.seconds.rounded().clock,
                           String(localized: analysis.goal.title)].joined(separator: " · ")
            return ReportRenderer.Pages(format: format, count: 1) { number in
                AnyView(ReportPage(title: .reportAnalysisTitle, details: details, number: number) { AnalysisReport(analysis: analysis) })
            }
        case .history:
            let range = (analyses.last!.date..<analyses[0].date).formatted(date: .abbreviated, time: .omitted)
            let details = String(localized: .dashboardAssessmentCount(analyses.count)) + " · " + range
            let chunks = format == .pdf ? stride(from: 0, to: analyses.count, by: ReportLayout.rowsPerPage).map {
                Array(analyses[$0..<min($0 + ReportLayout.rowsPerPage, analyses.count)])
            } : [analyses]
            return ReportRenderer.Pages(format: format, count: chunks.count) { number in
                AnyView(ReportPage(title: .dashboardAnalysisHistory, details: details, number: number) {
                    HistoryTable(analyses: chunks[(number?.0 ?? 1) - 1])
                })
            }
        }
    }

    struct ExportFailed: Error {}

    /// "Euphona 2026-11-09 2030", the way recordings are named.
    static func name(_ prefix: String = "Euphona", date: Date) -> String {
        "\(prefix) \(date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted)))"
    }
}

/// Draws report pages in light mode at a fixed size: a PDF page by page, or a PNG at twice the size.
@MainActor
struct ReportRenderer {
    struct Pages {
        var format: ExportFile.Format
        var count: Int
        /// The page for (number, count) in a PDF, or the one image for nil.
        var page: ((Int, Int)?) -> AnyView
    }

    var tint: Color

    func render(_ pages: Pages) -> Data? {
        switch pages.format {
        case .image: png(pages.page(nil))
        case .pdf: pdf((1...pages.count).map { pages.page(($0, pages.count)) })
        }
    }

    private func styled(_ page: AnyView, height: CGFloat?) -> some View {
        page
            .frame(width: ReportLayout.page.width, height: height, alignment: .top)
            .background(.white)
            .tint(tint)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
    }

    private func png(_ page: AnyView) -> Data? {
        let renderer = ImageRenderer(content: styled(page, height: nil))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private func pdf(_ pages: [AnyView]) -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: ReportLayout.page)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for page in pages {
            ImageRenderer(content: styled(page, height: ReportLayout.page.height)).render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }
}

/// Share as an image or a PDF, and the recording when there is one.
struct ExportItems: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    var content: ExportFile.Content
    var name: String
    var recording: RecordingFile?

    var body: some View {
        ForEach(ExportFile.Format.allCases, id: \.self) { format in
            ShareLink(item: ExportFile(content: content, format: format, name: name, container: modelContext.container, tint: theme.tint),
                      preview: SharePreview(Text(verbatim: name))) {
                Label { Text(format == .image ? .shareAsImage : .shareAsPdf) } icon: {
                    Image(systemName: format == .image ? "photo" : "doc.richtext")
                }
            }
        }
        if let recording {
            ShareLink(item: recording, preview: SharePreview(Text(.dashboardShareRecording))) {
                Label { Text(.dashboardShareRecording) } icon: { Image(systemName: "waveform") }
            }
        }
    }
}

/// The toolbar's share menu; on Mac it also saves the image or PDF to a file.
struct ExportMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(ErrorCenter.self) private var errors
    var content: ExportFile.Content
    var name: String
    var recording: RecordingFile?
    @State private var saving: ExportFile?

    var body: some View {
        Menu {
            ExportItems(content: content, name: name, recording: recording)
            #if os(macOS)
            Divider()
            ForEach(ExportFile.Format.allCases, id: \.self) { format in
                Button {
                    saving = ExportFile(content: content, format: format, name: name, container: modelContext.container, tint: theme.tint)
                } label: { Text(format == .image ? .saveAsImage : .saveAsPdf) }
            }
            #endif
        } label: {
            Label { Text(.shareTitle) } icon: { Image(systemName: "square.and.arrow.up") }
        }
        .help(Text(.shareTitle))
        #if os(macOS)
        .fileExporter(isPresented: Binding { saving != nil } set: { if !$0 { saving = nil } }, item: saving,
                      contentTypes: saving.map { [$0.format.type] } ?? [], defaultFilename: name) { result in
            if case .failure = result { errors.report(.errorExportFailed) }
        }
        #endif
    }
}
