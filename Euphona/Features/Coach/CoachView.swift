import EuphonaKit
import SwiftData
import SwiftUI

/// The Coach tab: today's lesson, talking with the coach, where the voice is now, and the skill path.
/// Lessons and talking about them start once an analysis has set where the voice is; until then the
/// tab asks for one and shows the path.
struct CoachView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ErrorCenter.self) private var errors
    @Environment(\.startAnalysis) private var startAnalysis
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CoachAttempt.date) private var allAttempts: [CoachAttempt]
    @Query(sort: \CoachNote.date, order: .reverse) private var notes: [CoachNote]
    @Query(sort: \VoiceCheckIn.date, order: .reverse) private var checkIns: [VoiceCheckIn]
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]
    @Query(sort: \CompletedLesson.date, order: .reverse) private var completed: [CompletedLesson]
    @Query(sort: \CoachRequest.date) private var requests: [CoachRequest]
    @State private var lesson: LessonSession?

    private var attempts: [AttemptSummary] {
        allAttempts.filter { $0.goal == settings.voiceGoal }.map(\.summary)
    }

    private var analyses: [VoiceBaseline] { VoiceBaseline.latest(records, goal: settings.voiceGoal) }

    private var plan: CoachPlan {
        CoachPlan(goal: settings.voiceGoal, records: records, attempts: allAttempts, requests: requests)
    }

    private var todaysCheckIn: CheckInSummary? {
        checkIns.first { Calendar.current.isDateInToday($0.date) }?.summary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let plan = plan
                VStack(alignment: .leading, spacing: 28) {
                    if plan.baseline == nil {
                        FirstAnalysisCard(start: startAnalysis)
                    } else {
                        TodayLessonCard(plan: plan, lesson: plan.lesson(checkIn: todaysCheckIn), doneToday: doneToday, start: start)
                    }
                    // Before the first analysis there is no lesson to talk about or change.
                    if let baseline = plan.baseline {
                        CoachSection(.coachTellTitle, footer: plan.requests != .none ? .coachTellActive : nil) {
                            VStack(alignment: .leading, spacing: 0) {
                                if let last = notes.first(where: { !$0.fromLearner }) {
                                    LastNote(note: last).padding(16)
                                    Divider().padding(.leading, 16)
                                }
                                QuickReplyBar(requests: plan.requests) { reply in
                                    errors.attempt(.errorChangeFailed) { try reply.send(store: HistoryStore(context: modelContext), plan: plan) }
                                }
                                .padding(.vertical, 12)
                                Divider().padding(.leading, 16)
                                NavigationLink(value: Route.coachChat) {
                                    LinkRow(title: .coachChatOpen, symbol: "bubble.left.and.text.bubble.right")
                                }
                                .buttonStyle(.card)
                            }
                        }
                        CoachSection(.coachStartingPoint, footer: .coachStartingPointFooter) {
                            StartingPoint(baseline: baseline).padding(.vertical, 14)
                        }
                    }
                    CoachSection(.coachPathTitle, footer: modelFooter) {
                        VStack(spacing: 0) {
                            ForEach(Skill.allCases, id: \.self) { skill in
                                let progress = plan.progress[skill]!
                                SkillRow(skill: skill, progress: progress, isFocus: skill == plan.focus,
                                         today: skill == plan.focus ? plan.focusLevel : progress.level)
                                if skill != Skill.allCases.last { Divider().padding(.leading, 74) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(Text(.tabCoach))
            .appRoutes()
            .toolbar { RootToolbar() }
        }
        #if os(iOS)
        .fullScreenCover(item: $lesson) { LessonView(session: $0) }
        #else
        .sheet(item: $lesson) { LessonView(session: $0).frame(minWidth: 560, minHeight: 760) }
        #endif
    }

    /// A lesson toward this goal was taken to its end today.
    private var doneToday: Bool {
        completed.contains { Calendar.current.isDateInToday($0.date) && $0.goalRaw == settings.voiceGoal.rawValue }
    }

    private var modelFooter: LocalizedStringResource {
        guard LanguageCoach.isAvailable(settings.coachModel) else { return .coachModelFooterWritten }
        return settings.coachModel == .privateCloud ? .coachModelFooterCloud : .coachModelFooterDevice
    }

    private func start() {
        lesson = LessonSession(goal: settings.voiceGoal, analyses: analyses, attempts: attempts, requests: plan.requests, checkIn: todaysCheckIn)
    }
}

extension LessonSession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// A titled card on the Coach tab, with an optional note under it.
private struct CoachSection<Content: View>: View {
    var title: LocalizedStringResource
    var footer: LocalizedStringResource?
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringResource, footer: LocalizedStringResource? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: .rect(cornerRadius: 22))
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The coach's latest message.
private struct LastNote: View {
    var note: CoachNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.bubble").font(.title3).foregroundStyle(.tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: note.text).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                Text(note.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A row that opens a screen, the way Progress lists its links.
private struct LinkRow: View {
    var title: LocalizedStringResource
    var symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 26)
            Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(.rect)
        .hoverCard(cornerRadius: 22)
    }
}

/// Before any analysis toward the goal: the one analysis every target grows from.
private struct FirstAnalysisCard: View {
    @Environment(\.theme) private var theme
    var start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                IconTile(symbol: "waveform", accent: theme.deepBlue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(.coachFirstAnalysisTitle).font(.title2.bold())
                    Text(.coachFirstAnalysisBody).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: start) {
                Label { Text(.analysisInferenceTitle) } icon: { Image(systemName: "mic.fill") }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 26))
    }
}

/// The day's lesson: its focus and level, its steps, and the one button that starts it.
private struct TodayLessonCard: View {
    @Environment(\.theme) private var theme
    var plan: CoachPlan
    var lesson: Lesson
    var doneToday: Bool
    var start: () -> Void

    private var steps: [Exercise] { lesson.steps.map(plan.exercise(for:)) }

    private var minutes: Int {
        // Each step's time plus about a minute to read and review it.
        Int((steps.reduce(0) { $0 + $1.seconds + 60 } / 60).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                IconTile(symbol: doneToday ? "checkmark" : lesson.isRest ? "leaf" : lesson.focus.symbol, accent: theme.deepBlue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(doneToday ? .coachDoneToday : .coachTodaysLesson).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(lesson.isRest ? .coachRestDay : lesson.focus.title).font(.title2.bold())
                    HStack(spacing: 6) {
                        if !lesson.isRest {
                            LevelText(level: plan.focusLevel, levels: ExerciseLibrary.levels(of: lesson.focus),
                                      earned: plan.progress[lesson.focus]?.level ?? 1)
                            Text(verbatim: "·")
                        }
                        Text(.coachLessonLength(minutes))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    Label { Text(verbatim: step.title) } icon: { Image(systemName: step.symbol) }
                        .labelStyle(.iconOnly)
                        .font(.footnote.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(.tint.opacity(0.12), in: .circle)
                        .foregroundStyle(.tint)
                        .help(Text(verbatim: step.title))
                }
            }
            Button(action: start) {
                Label { Text(doneToday ? .coachPracticeAgain : .coachStartLesson) } icon: { Image(systemName: "play.fill") }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 26))
    }
}

/// Where the voice is now, from the latest analyses: what today's targets grow from.
private struct StartingPoint: View {
    var baseline: VoiceBaseline

    var body: some View {
        HStack(spacing: 0) {
            value(.coachSkillPitch, baseline.speakingF0Hz.map { $0.hertz() } ?? "--")
            Divider()
            value(.timbreTitle, baseline.timbre.formatted(decimals: 0))
            Divider()
            value(.scoreFinalScore, baseline.score.formatted(decimals: 0))
        }
        .frame(minHeight: 56)
    }

    private func value(_ title: LocalizedStringResource, _ text: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: text).font(.title3.weight(.semibold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Level 3 of 4", with an arrow when today's requests moved it from the earned level.
private struct LevelText: View {
    var level: Int
    var levels: Int
    var earned: Int

    var body: some View {
        HStack(spacing: 3) {
            if level != earned {
                Image(systemName: level > earned ? "arrow.up" : "arrow.down").foregroundStyle(.tint)
            }
            Text(.coachSkillLevel(level, levels)).monospacedDigit()
        }
    }
}

/// One skill on the path: how far along it is, and the focus skill's level today.
private struct SkillRow: View {
    var skill: Skill
    var progress: SkillProgress
    var isFocus: Bool
    var today: Int

    var body: some View {
        HStack(spacing: 14) {
            SkillRing(fraction: progress.fraction, symbol: progress.isComplete ? "checkmark" : skill.symbol,
                      color: progress.isComplete ? Tokens.success : nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.title).font(.body.weight(isFocus ? .semibold : .regular))
                Text(skill.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Group {
                if progress.isComplete {
                    Text(.coachSkillComplete)
                } else {
                    LevelText(level: today, levels: progress.levels, earned: progress.level)
                }
            }
            .font(.subheadline)
            .foregroundStyle(isFocus ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// How far along a skill is, as a ring in the theme's tint around the skill's symbol.
private struct SkillRing: View {
    var fraction: Double
    var symbol: String
    /// Nil for the tint.
    var color: Color?

    var body: some View {
        let style = color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint)
        ZStack {
            Circle().stroke(.tint.opacity(0.15), lineWidth: 4)
            Circle().trim(from: 0, to: fraction)
                .stroke(style, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(style)
        }
        .frame(width: 44, height: 44)
    }
}
