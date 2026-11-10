import EuphonaKit
import SwiftData
import SwiftUI

/// Feedback is posted as a GitHub issue from the person's own account: the app fills in the message
/// and, if they want, diagnostics they can read first, then opens the new-issue page. The app itself
/// sends nothing. Issues are public, so the diagnostics leave out anything personal, such as the goal.
struct FeedbackView: View {
    @Environment(\.openURL) private var openURL
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]
    @State private var message = ""
    @State private var includesDiagnostics = true

    var body: some View {
        Form {
            Section {
                TextField(text: $message, axis: .vertical) { Text(.feedbackPlaceholder) }
                    .lineLimit(6...14)
            } footer: { Text(.feedbackFooter) }
            Section {
                Toggle(isOn: $includesDiagnostics) { Text(.feedbackDiagnostics) }
                if includesDiagnostics {
                    DisclosureGroup {
                        Text(verbatim: diagnosticsText)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: { Text(.feedbackDiagnosticsShow) }
                }
            } footer: { Text(.feedbackDiagnosticsFooter) }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(.feedbackTitle))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { openURL(issueURL) } label: { Text(.feedbackSend) }
                    .disabled(trimmedMessage.isEmpty)
            }
        }
    }

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Everything added besides the message, in the order shown. Nothing personal: the issue is public.
    private var diagnostics: [(key: String, value: String)] {
        let info = Bundle.main.infoDictionary
        var machine = utsname()
        uname(&machine)
        let model = withUnsafeBytes(of: machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return [
            ("app", "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"),
            ("models", EuphonaAnalyzer.modelVersion),
            ("device", model),
            ("system", ProcessInfo.processInfo.operatingSystemVersionString),
            ("language", Locale.preferredLanguages.first ?? "?"),
            ("recent scores", records.prefix(5).map { $0.finalScore.formatted(decimals: 0) }.joined(separator: ", ")),
        ]
    }

    private var diagnosticsText: String { diagnostics.map { "\($0.key): \($0.value)" }.joined(separator: "\n") }

    /// The new-issue page with the title (the message's first line) and body filled in.
    private var issueURL: URL {
        let title = String(trimmedMessage.prefix { !$0.isNewline }.prefix(Self.titleLength))
        var body = trimmedMessage
        if includesDiagnostics { body += "\n\n```\n\(diagnosticsText)\n```" }
        var components = URLComponents(url: Self.newIssue, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    private static let titleLength = 80
    private static let newIssue = URL(string: "https://github.com/Lumysia/Euphona/issues/new")!

    static let windowID = "feedback"
}
