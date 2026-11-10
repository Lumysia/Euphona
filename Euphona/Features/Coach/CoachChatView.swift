import EuphonaKit
import SwiftData
import SwiftUI

/// Talking with the coach: the whole conversation, including what it said after attempts, quick
/// replies for the usual requests, and free text when a language model is on.
struct CoachChatView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ErrorCenter.self) private var errors
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CoachNote.date) private var notes: [CoachNote]
    @Query(sort: \CoachAttempt.date, order: .reverse) private var attempts: [CoachAttempt]
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]
    @Query(sort: \CoachRequest.date) private var requests: [CoachRequest]
    @State private var draft = ""
    @State private var thinking = false
    @FocusState private var typing: Bool

    private var plan: CoachPlan {
        CoachPlan(goal: settings.voiceGoal, records: records, attempts: attempts, requests: requests)
    }

    private var canTalk: Bool { LanguageCoach.isAvailable(settings.coachModel) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if notes.isEmpty {
                    Text(canTalk ? LocalizedStringResource.coachChatEmpty : .coachChatEmptyWritten)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.vertical, 40).padding(.horizontal, 24)
                }
                ForEach(notes) { note in
                    MessageBubble(text: note.text, fromLearner: note.fromLearner, date: note.date)
                    // A suggested change waits for the learner's tap, and only while it is the latest word.
                    if note.id == notes.last?.id, let suggestion = note.suggestion, plan.isChanged(by: suggestion) {
                        let reply = QuickReply(suggestion)
                        HStack {
                            Button { send(reply) } label: { Label { Text(reply.label) } icon: { Image(systemName: reply.symbol) } }
                                .buttonStyle(.glassProminent)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                    }
                }
                if thinking {
                    MessageBubble(text: String(localized: .coachThinking), fromLearner: false, date: nil)
                        .phaseAnimator([0.4, 1]) { content, opacity in content.opacity(opacity) }
                        .id("thinking")
                }
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .animation(.smooth, value: notes.count)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.groupedBackground.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 8) {
                if plan.baseline != nil { QuickReplyBar(requests: plan.requests, send: send) }
                if canTalk {
                    composer
                } else {
                    Text(.coachChatNeedsModel).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 8)
        }
        .navigationTitle(Text(.coachChatTitle))
        #if DEBUG
        .task {
            guard let message = DemoData.message else { return }
            draft = message
            send()
        }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(text: $draft, axis: .vertical) { Text(.coachChatPlaceholder) }
                .lineLimit(1...5)
                .focused($typing)
                .onSubmit(send)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
            Button(action: send) {
                Label { Text(.coachChatSend) } icon: { Image(systemName: "arrow.up") }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
    }

    private func send(_ reply: QuickReply) {
        errors.attempt(.errorChangeFailed) { try reply.send(store: HistoryStore(context: modelContext), plan: plan) }
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !thinking else { return }
        let snapshot = LanguageCoach.Snapshot(plan: plan, attempts: attempts, records: records, notes: notes.suffix(CoachChat.contextMessages).reversed())
        let store = HistoryStore(context: modelContext)
        errors.attempt(.errorChangeFailed) { try store.addNote(message, fromLearner: true) }
        draft = ""
        thinking = true
        Task {
            let answer = await CoachChat.answer(message, plan: plan, snapshot: snapshot, choice: settings.coachModel)
            errors.attempt(.errorChangeFailed) {
                try store.addNote(answer?.text ?? String(localized: .coachChatFailed), suggestion: answer?.suggestion)
            }
            thinking = false
        }
    }
}

/// One message: the learner's on the trailing side tinted with the accent, the coach's on the leading side.
private struct MessageBubble: View {
    var text: String
    var fromLearner: Bool
    var date: Date?

    var body: some View {
        HStack {
            if fromLearner { Spacer(minLength: 48) }
            Text(verbatim: text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(fromLearner ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(Color.groupedCell),
                            in: .rect(cornerRadius: 20))
                .textSelection(.enabled)
                .help(date.map { Text($0, format: .dateTime) } ?? Text(verbatim: ""))
            if !fromLearner { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(fromLearner ? LocalizedStringResource.coachChatYou : .coachChatCoach) + Text(verbatim: ": \(text)"))
    }
}
