import CloudKit
import EuphonaKit
import SwiftData
import SwiftUI

/// Sending feedback: a message, an optional address for a reply, and anonymous diagnostics the person
/// can read before sending. It goes to the app's CloudKit public database, which Apple hosts. The
/// record holds no identifier of ours; CloudKit adds only its own opaque per-app creator ID, which
/// reveals neither the person's name nor their Apple Account.
struct FeedbackView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]
    @State private var message = ""
    @State private var contact = ""
    @State private var includesDiagnostics = true
    @State private var state = SendState.editing

    enum SendState: Equatable { case editing, sending, sent, failed(LocalizedStringResource) }

    var body: some View {
        Form {
            if state == .sent {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Tokens.success)
                            .symbolEffect(.bounce, value: state)
                        Text(.feedbackSentTitle).font(.title3.bold())
                        Text(.feedbackSentBody).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section {
                    TextField(text: $message, axis: .vertical) { Text(.feedbackPlaceholder) }
                        .lineLimit(6...14)
                } footer: { Text(.feedbackFooter) }
                Section {
                    TextField(text: $contact) { Text(.feedbackContactPlaceholder) }
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } footer: { Text(.feedbackContactFooter) }
                Section {
                    Toggle(isOn: $includesDiagnostics) { Text(.feedbackDiagnostics) }
                    if includesDiagnostics {
                        DisclosureGroup {
                            Text(verbatim: diagnostics.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } label: { Text(.feedbackDiagnosticsShow) }
                    }
                } footer: { Text(.feedbackDiagnosticsFooter) }
                if case .failed(let reason) = state {
                    Section { Label { Text(reason) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.warning) } }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(.feedbackTitle))
        .toolbar {
            if state != .sent {
                ToolbarItem(placement: .confirmationAction) {
                    if state == .sending {
                        ProgressView()
                    } else {
                        Button { Task { await send() } } label: { Text(.feedbackSend) }
                            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .animation(.smooth, value: state)
    }

    /// Everything sent besides the message, in the order shown. No identifier of any kind.
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
            ("goal", settings.voiceGoal.rawValue),
            ("coach", settings.coachModel.rawValue),
            ("recent scores", records.prefix(5).map { $0.finalScore.formatted(decimals: 0) }.joined(separator: ", ")),
        ]
    }

    private func send() async {
        state = .sending
        let container = CKContainer(identifier: Self.container)
        guard (try? await container.accountStatus()) == .available else { state = .failed(.feedbackNeedsIcloud); return }
        let record = CKRecord(recordType: "Feedback")
        record["message"] = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contact.isEmpty { record["contact"] = contact }
        if includesDiagnostics {
            record["diagnostics"] = diagnostics.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        }
        do {
            _ = try await container.publicCloudDatabase.save(record)
            state = .sent
        } catch {
            state = .failed(.feedbackFailed)
        }
    }

    static let windowID = "feedback"

    /// The app's iCloud container, the same one history syncs through.
    static let container = "iCloud.net.lumysia.Euphona"
}
