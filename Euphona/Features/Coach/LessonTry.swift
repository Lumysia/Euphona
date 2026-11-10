import Observation
import EuphonaKit
import SwiftUI

/// Counts a try's time only while its tool is listening.
@MainActor @Observable
final class TryTimer {
    private(set) var accumulated = 0.0
    private(set) var since: Date?

    func set(running: Bool, now: Date = .now) {
        if running, since == nil { since = now }
        if !running, let since { accumulated += now.timeIntervalSince(since); self.since = nil }
    }

    func elapsed(at now: Date = .now) -> Double { accumulated + (since.map { now.timeIntervalSince($0) } ?? 0) }
}

/// The try: the exercise's tool, with the time left and Done in the bar. The try ends by itself when
/// its time is up.
struct LessonTry: View {
    var session: LessonSession
    var finish: (AttemptMetrics) -> Void
    @Environment(AppSettings.self) private var settings
    @State private var timer = TryTimer()
    @State private var finished = false

    private var exercise: Exercise { session.exercise }

    var body: some View {
        tool
            .toolbar {
                if exercise.tool != .reading, exercise.tool != .conversation {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { end() } label: { Text(.coachDone) }
                    }
                    ToolbarItem(placement: .primaryAction) { remaining }
                }
            }
            .onChange(of: isRunning, initial: true) { timer.set(running: isRunning) }
            .task(id: timer.since) {
                guard timer.since != nil else { return }
                let left = exercise.seconds - timer.elapsed()
                do { try await Task.sleep(for: .seconds(max(left, 0))) } catch { return }
                end()
            }
    }

    @ViewBuilder private var tool: some View {
        switch exercise.tool {
        case .pitch(let target): PitchView(target: target, monitor: session.pitch)
        case .timbre: TimbreView(target: exercise.goal.pass...100, monitor: session.timbre)
        case .resonance: ResonanceView(monitor: session.resonance)
        case .timed: TimedExercise(exercise: exercise, timer: timer)
        case .reading: RecordedTry(exercise: exercise, prompt: nil) { finishRecorded($0) }
        case .conversation: RecordedTry(exercise: exercise, prompt: session.talkPrompt) { finishRecorded($0) }
        }
    }

    private var remaining: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, exercise.seconds - timer.elapsed(at: context.date))
            Text(verbatim: left.clock)
                .font(.headline.monospacedDigit())
                .foregroundStyle(timer.since == nil ? .secondary : .primary)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel(Text(.coachTimeLeft(left.clock)))
        }
    }

    private var isRunning: Bool {
        switch exercise.tool {
        case .pitch: session.pitch.state == .running
        case .timbre: session.timbre.input.state == .running
        case .resonance: session.resonance.input.state == .running
        case .timed: timer.since != nil
        case .reading, .conversation: false
        }
    }

    private func aligned(_ feminine: Double) -> Double { session.goal == .feminine ? feminine : 100 - feminine }

    private func end() {
        guard !finished else { return }
        finished = true
        timer.set(running: false)
        let seconds = timer.elapsed()
        var metrics = AttemptMetrics(seconds: seconds)
        switch exercise.tool {
        case .pitch(let target):
            session.pitch.pause()
            metrics.onTarget = session.pitch.share(on: target).map { $0 * 100 }
            let voiced = session.pitch.points.compactMap(\.hz)
            metrics.speakingF0Hz = EuphonaResult.F0Metrics.median(voiced.map { Double($0) })
        case .timbre:
            session.timbre.stop()
            let scores = session.timbre.frames.map(\.score)
            metrics.timbre = scores.isEmpty ? nil : aligned(scores.reduce(0, +) / Double(scores.count))
        case .resonance:
            session.resonance.stop()
            let values = session.resonance.brightnessHistory
            metrics.brightness = values.isEmpty ? nil : aligned(values.reduce(0, +) / Double(values.count))
        case .timed, .reading, .conversation:
            break
        }
        finish(metrics)
    }

    private func finishRecorded(_ outcome: AnalysisOutcome) {
        guard !finished else { return }
        finished = true
        let result = outcome.result
        if exercise.tool == .conversation { session.transcribe(outcome.audio, speechSeconds: result.speech.seconds) }
        finish(AttemptMetrics(seconds: result.speech.seconds, timbre: aligned(result.timbre.score),
                              flow: result.flow.score, score: result.composite.finalScore,
                              speakingF0Hz: result.f0.speakingHz))
    }
}

/// A timed warm-up: the instructions large, a ring for the time, and start and pause.
private struct TimedExercise: View {
    var exercise: Exercise
    var timer: TryTimer

    var body: some View {
        InstrumentPanel(title: .coachWarmUp, reading: reading) {
            TimelineView(.animation(paused: timer.since == nil)) { context in
                let fraction = min(timer.elapsed(at: context.date) / exercise.seconds, 1)
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 14)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: exercise.symbol)
                        .scaledFont(size: 48, weight: .semibold)
                        .foregroundStyle(.tint)
                        .symbolEffect(.breathe, options: .repeat(.continuous), isActive: timer.since != nil)
                }
                .frame(width: 200, height: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } controls: {
            InstrumentPrimaryButton(title: timer.since == nil ? .coachStart : .coachPause,
                                    symbol: timer.since == nil ? "play.fill" : "pause.fill") {
                timer.set(running: timer.since == nil)
            }
        }
    }

    private var reading: InstrumentReading {
        InstrumentReading(value: nil, symbol: exercise.symbol, detail: Text(verbatim: exercise.title))
    }
}

/// A recorded try: the analysis screen, with the passage or a prompt to talk about.
private struct RecordedTry: View {
    var exercise: Exercise
    var prompt: String?
    var done: (AnalysisOutcome) -> Void
    @State private var recording = false
    @State private var outcome: AnalysisOutcome?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: exercise.symbol).scaledFont(size: 52, weight: .semibold).foregroundStyle(.tint)
            Text(verbatim: exercise.title).font(.title2.bold())
            if let prompt {
                Text(verbatim: prompt).font(.title3).multilineTextAlignment(.center)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.groupedCell, in: .rect(cornerRadius: 22))
            }
            Text(.coachRecordedHint).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 560, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background(Color.groupedBackground.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            LessonPrimaryButton(title: .coachRecord, symbol: "mic.fill") { recording = true }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $recording, onDismiss: deliver) { analysis }
        #else
        .sheet(isPresented: $recording, onDismiss: deliver) { analysis.frame(minWidth: 520, minHeight: 720) }
        #endif
    }

    private var analysis: some View {
        AnalysisView(prompt: prompt) { outcome = $0 }
    }

    private func deliver() {
        if let outcome { done(outcome) }
    }
}

/// The coach's answer to a try, and the choice of what comes next.
struct LessonReviewView: View {
    var session: LessonSession

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let outcome = session.outcome {
                    Image(systemName: outcome.symbol)
                        .scaledFont(size: 64, weight: .semibold)
                        .foregroundStyle(outcome.color)
                        .symbolEffect(.bounce, value: outcome)
                        .padding(.top, 20)
                    Text(outcome.title).font(.title.bold())
                    if let value = session.value, session.exercise.tool != .timed {
                        Text(.coachMeasuredAgainstGoal(session.exercise.describe(value), session.exercise.describe(session.exercise.goal.pass)))
                            .font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: session.review?.byModel == true ? "apple.intelligence" : "quote.bubble")
                        .font(.title3)
                        .foregroundStyle(.tint)
                    if let review = session.review {
                        Text(verbatim: review.message).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.blurReplace)
                    } else {
                        Text(.coachThinking).font(.body).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .phaseAnimator([0.4, 1]) { content, opacity in content.opacity(opacity) }
                    }
                }
                .padding(18)
                .background(Color.groupedCell, in: .rect(cornerRadius: 22))
                .animation(.smooth, value: session.review)
                if let review = session.review {
                    Group {
                        if let next = session.destination(of: review.adjustment) {
                            Label { Text(.coachNextStep(next.title, next.goalSummary)) }
                                icon: { Image(systemName: review.adjustment == .harder ? "arrow.up.right" : "arrow.turn.down.right") }
                        } else {
                            Label { Text(.coachNextFinish) } icon: { Image(systemName: "flag.checkered") }
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
                if let transcript = session.transcript {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(.coachYouSaid).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text(verbatim: transcript.text).font(.body)
                        if let rate = transcript.wordsPerMinute {
                            Text(.coachWordsPerMinute(rate.formatted(decimals: 0))).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.groupedCell, in: .rect(cornerRadius: 22))
                    .transition(.blurReplace)
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            if let first = session.choices.first {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(session.choices.dropFirst(), id: \.self) { choice in
                            Button { session.follow(choice) } label: { Text(choice.title).font(.headline).padding(.horizontal, 8).frame(minHeight: 52) }
                                .buttonStyle(.glass)
                        }
                        Button { session.follow(first) } label: { Text(first.title).font(.headline).padding(.horizontal, 8).frame(minHeight: 52) }
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .controlSize(.large)
                .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.success, trigger: session.outcome == .passed)
    }
}

/// The end of a lesson: every step's outcome.
/// The lesson's end: what each step did, and how the voice feels now. A tired or sore voice after
/// practice turns the rest of the day into rest, like the check-in before it.
struct LessonDoneView: View {
    var results: [(exercise: Exercise, outcome: Outcome)]
    /// Saves how the voice feels after the lesson (1 sore … 5 fresh).
    var saveComfort: (Int) -> Void
    var close: () -> Void
    @State private var comfort: Int?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").scaledFont(size: 64, weight: .semibold).foregroundStyle(.tint)
                        .symbolEffect(.bounce, options: .nonRepeating)
                    Text(.coachLessonDone).font(.title.bold())
                    Text(.coachLessonDoneBody).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                    Label { Text(verbatim: result.exercise.title) } icon: {
                        Image(systemName: result.outcome.symbol).foregroundStyle(result.outcome.color)
                    }
                    .badge(Text(result.outcome.title))
                }
            }
            Section {
                ComfortPicker(comfort: $comfort)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .onChange(of: comfort) { if let comfort { saveComfort(comfort) } }
            } header: { Text(.coachAfterTitle) } footer: {
                if let comfort, comfort <= 2 { Text(.coachAfterTired) }
            }
        }
        .safeAreaBar(edge: .bottom) {
            LessonPrimaryButton(title: .coachFinish, symbol: "checkmark", action: close)
        }
    }
}
