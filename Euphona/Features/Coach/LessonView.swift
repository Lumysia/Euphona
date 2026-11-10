import EuphonaKit
import SwiftData
import SwiftUI

/// A lesson, one step at a time. Full screen on iPhone and iPad, a sheet on Mac.
struct LessonView: View {
    @State var session: LessonSession
    @Environment(AppSettings.self) private var settings
    @Environment(ErrorCenter.self) private var errors
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CoachAttempt.date, order: .reverse) private var attempts: [CoachAttempt]
    @Query(sort: \CoachNote.date, order: .reverse) private var notes: [CoachNote]
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]
    @Query(sort: \CompletedLesson.date) private var lessons: [CompletedLesson]
    /// Shown before the summary when finishing this lesson extended the streak.
    @State private var streak: Streak?

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .checkIn: CheckInView { session.checkIn($0); save($0) }
                case .explain: ExerciseIntro(exercise: session.exercise) { session.beginTry() }
                case .trying: LessonTry(session: session, finish: finish)
                case .reviewing: LessonReviewView(session: session)
                case .finished:
                    if let streak {
                        StreakCelebration(streak: streak) { withAnimation(.smooth(duration: 0.5)) { self.streak = nil } }
                    } else {
                        LessonDoneView(results: session.results, saveComfort: { comfort in
                            errors.attempt(.errorChangeFailed) { try HistoryStore(context: modelContext).addCheckIn(comfort: comfort, pain: false) }
                        }) { dismiss() }
                    }
                }
            }
            .transition(.blurReplace)
            .animation(.smooth(duration: 0.4), value: session.phase)
            .onChange(of: session.phase) { if session.phase == .finished { complete() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                if session.phase != .checkIn, session.phase != .finished {
                    ToolbarItem(placement: .principal) { StepProgress(step: session.stepIndex, count: session.stepCount) }
                }
                if session.phase == .explain || session.phase == .reviewing {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(QuickReply.inLesson(session.lesson), id: \.self) { reply in
                                Button { tell(reply) } label: { Label { Text(reply.label) } icon: { Image(systemName: reply.symbol) } }
                            }
                        } label: {
                            Label { Text(.coachTellTitle) } icon: { Image(systemName: "bubble.left.and.text.bubble.right") }
                        }
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .errorAlerts(errors)
    }

    /// Records the finished lesson; the day's first practice celebrates the streak first.
    private func complete() {
        let now = Date.now
        let activity = records.map(\.date) + lessons.map(\.date) + [now]
        // Analyses recorded during the lesson are part of it, so it counts from its start.
        if Streak.extends(at: session.started, activity: activity) { streak = Streak(activity: activity) }
        errors.attempt(.errorChangeFailed) { try HistoryStore(context: modelContext).completeLesson(goal: session.goal, date: now) }
    }

    private func save(_ checkIn: CheckInSummary) {
        errors.attempt(.errorChangeFailed) { try HistoryStore(context: modelContext).addCheckIn(comfort: checkIn.comfort, pain: checkIn.pain) }
    }

    private func finish(_ metrics: AttemptMetrics) {
        Task {
            await session.finish(metrics, store: HistoryStore(context: modelContext), choice: settings.coachModel,
                                 snapshot: { .init(plan: session.plan, attempts: attempts, records: records, notes: notes) },
                                 errors: errors)
        }
    }

    /// Tells the coach how the lesson feels; the lesson follows at once.
    private func tell(_ reply: QuickReply) {
        let store = HistoryStore(context: modelContext)
        errors.attempt(.errorChangeFailed) {
            guard try reply.send(store: store, plan: session.plan) else { return }
            session.follow(reply.request, requests: try store.requests())
        }
    }
}

/// "Step 2 of 4" with a thin bar.
private struct StepProgress: View {
    var step: Int
    var count: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(.coachStepOf(step + 1, count)).font(.subheadline.weight(.semibold)).monospacedDigit()
            ProgressView(value: Double(step + 1), total: Double(count))
                .progressViewStyle(.linear)
                .frame(width: 90)
        }
        .accessibilityElement(children: .combine)
    }
}

/// How the voice feels today. Pain or a very tired voice turns the lesson into rest.
private struct CheckInView: View {
    var done: (CheckInSummary) -> Void
    @State private var comfort = 3
    @State private var pain = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(.coachCheckInTitle).font(.title.bold()).multilineTextAlignment(.center)
                    Text(.coachCheckInBody).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                ComfortPicker(comfort: Binding(get: { comfort }, set: { comfort = $0 ?? comfort }))
                Toggle(isOn: $pain) { Text(.coachCheckInPain) }
                    .padding(16)
                    .background(Color.groupedCell, in: .rect(cornerRadius: 18))
                Text(.coachCheckInFooter).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            LessonPrimaryButton(title: .coachContinue, symbol: "arrow.right") { done(CheckInSummary(comfort: comfort, pain: pain)) }
        }
    }
}

/// The step before trying: what to do, why, and how it will be measured.
private struct ExerciseIntro: View {
    @Environment(\.theme) private var theme
    var exercise: Exercise
    var start: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    IconTile(symbol: exercise.symbol, accent: theme.deepBlue)
                    VStack(alignment: .leading, spacing: 4) {
                        if let skill = exercise.skill {
                            Text(skill.title).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                        } else {
                            Text(.coachWarmUp).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                        }
                        Text(verbatim: exercise.title).font(.title.bold())
                    }
                }
                Text(verbatim: exercise.why).font(.body).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(exercise.steps.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                        StepLine(line: String(line))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.groupedCell, in: .rect(cornerRadius: 22))
                HStack(spacing: 10) {
                    Label { Text(Duration.seconds(exercise.seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))) }
                        icon: { Image(systemName: "timer") }
                    if exercise.tool != .timed {
                        Label { Text(verbatim: exercise.describe(exercise.goal.pass)) } icon: { Image(systemName: "target") }
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                Label { Text(verbatim: exercise.tip) } icon: { Image(systemName: "lightbulb").foregroundStyle(.yellow) }
                    .font(.callout)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            LessonPrimaryButton(title: .coachStart, symbol: "play.fill", action: start)
        }
    }
}

/// "1. Hold a straw…": the number set apart so wrapped lines align.
private struct StepLine: View {
    var line: String

    var body: some View {
        let parts = line.split(separator: " ", maxSplits: 1)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if parts.count == 2, parts[0].last == "." {
                Text(verbatim: String(parts[0].dropLast()))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.tint)
                    .frame(minWidth: 18, alignment: .trailing)
                Text(verbatim: String(parts[1]))
            } else {
                Text(verbatim: line)
            }
        }
        .font(.body)
    }
}

/// The lesson's main button, a prominent glass capsule above the bottom edge.
struct LessonPrimaryButton: View {
    var title: LocalizedStringResource
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .font(.headline)
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .padding(.bottom, 12)
    }
}
