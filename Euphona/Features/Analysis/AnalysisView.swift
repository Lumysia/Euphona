import EuphonaKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The full-screen voice analysis: read, record, analyze, see the result.
struct AnalysisView: View {
    @Environment(ErrorCenter.self) private var errors
    /// The Mac window it opens in.
    static let windowID = "analysis"

    @Environment(AppSettings.self) private var settings
    @Environment(VoiceEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]
    @Query(sort: \CompletedLesson.date) private var lessons: [CompletedLesson]
    @State private var session = RecordSession()
    @State private var importing = false
    /// Something to talk about instead of the reading passage, for a lesson's free-speaking step.
    private let prompt: String?
    /// Called once per finished analysis, for a lesson's recorded steps.
    private let onFinish: (AnalysisOutcome) -> Void

    init(prompt: String? = nil, onFinish: @escaping (AnalysisOutcome) -> Void = { _ in }) {
        self.prompt = prompt
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Group {
                switch session.state {
                case .finished(let outcome):
                    ResultReveal(content: ResultContent(outcome), streak: extendedStreak(outcome))
                        .toolbar { recordAgainButton }
                        .transition(.blurReplace)
                case .failed(let failure):
                    CaptureFailureView(failure: failure) { Task { await start() } }.transition(.blurReplace)
                default:
                    capture.transition(.blurReplace)
                        .toolbar { importButton }
                }
            }
            .animation(.smooth(duration: 0.5), value: stateKey)
            .appRoutes()
            #if os(iOS)
            // On Mac the window's own close button (⌘W) closes it.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        // Closing (button or swipe) abandons a recording or analysis in progress.
        .onDisappear { Task { await session.cancel() } }
        .onChange(of: stateKey) {
            if case .finished(let outcome) = session.state { onFinish(outcome) }
        }
        .errorAlerts(errors)
    }

    /// The stage, passage and button fill the screen. They sit in a scroll view that never scrolls: the
    /// navigation bar binds to the first scroll view it finds, and when that was the passage, scrolling it
    /// changed the bar and pushed the whole page up (29 pt on iPhone Duo).
    private var capture: some View {
        GeometryReader { proxy in
            ScrollView {
                captureContent.frame(height: proxy.size.height)
            }
            .scrollDisabled(true)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { AmbientBackground(balance: session.capture.orbBalance(resting: restingBalance)) }
        .navigationTitle(Text(.analysisInferenceTitle))
    }

    private var captureContent: some View {
        VStack(spacing: 0) {
            CaptureStage(
                phase: phase,
                requiredSpeechSeconds: RecordSession.minimumSpeechSeconds,
                amplitudes: amplitudes,
                balance: session.capture.orbBalance(resting: restingBalance),
                idleTitle: .clickToRecord,
                idleSubtitle: .analysisRecordingMinimum,
                baseDiameter: 260
            )
            Group {
                if let prompt {
                    ScrollView {
                        Text(verbatim: prompt).font(.title3).multilineTextAlignment(.center).padding(24)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ReadingPassageView(canSwitch: !isRecording && !isAnalyzing)
                }
            }
                .frame(minHeight: 150, maxHeight: .infinity)
                .background(.background.secondary, in: .rect(cornerRadius: 26))
                .clipShape(.rect(cornerRadius: 26))
                .padding(.horizontal, 20)
                .padding(.top, 8)
            CaptureButton(isRecording: isRecording, isEnabled: !isAnalyzing) { toggle() }
                .padding(.vertical, 24)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    /// The streak, when this analysis was the day's first practice (not inside a lesson, whose
    /// end celebrates instead).
    private func extendedStreak(_ outcome: AnalysisOutcome) -> Streak? {
        guard prompt == nil, let id = outcome.recordID, let record = modelContext.model(for: id) as? AnalysisRecord else { return nil }
        let activity = records.map(\.date) + lessons.map(\.date) + [record.date]
        return Streak.extends(at: record.date, activity: activity) ? Streak(activity: activity) : nil
    }

    /// Analyzes an audio or video file instead of the microphone; not inside a lesson, whose steps
    /// are practice.
    @ToolbarContentBuilder private var importButton: some ToolbarContent {
        if prompt == nil {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: {
                    Label { Text(.analysisImportAudio) } icon: { Image(systemName: "square.and.arrow.down") }
                }
                .help(Text(.analysisImportAudio))
                .disabled(session.isBusy)
                .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie]) { result in
                    guard case .success(let url) = result else { return }
                    Task { await session.analyze(file: url, .init(engine: engine, settings: settings, context: modelContext, errors: errors)) }
                }
            }
        }
    }

    private var recordAgainButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await start() } } label: {
                Label { Text(.recordingAgain) } icon: { Image(systemName: "arrow.counterclockwise") }
            }
        }
    }

    // MARK: State

    /// Which screen the session shows, for the transition between them.
    private var stateKey: Int {
        switch session.state {
        case .finished: 2
        case .failed: 3
        default: 1
        }
    }

    private var isRecording: Bool { if case .recording = session.state { true } else { false } }
    private var isAnalyzing: Bool { if case .analyzing = session.state { true } else { false } }

    private var amplitudes: [Float] { isRecording ? session.capture.amplitudes : [] }

    private var phase: CaptureStage.Phase {
        switch session.state {
        case .recording: .recording(elapsed: session.capture.elapsed, speech: session.capture.speechSeconds)
        case .analyzing(let progress): .analyzing(progress: Self.overall(progress), stage: Self.stageLabel(progress))
        default: .idle
        }
    }

    /// The orb rests at how the latest analysis read, or in the middle before any analysis.
    private var restingBalance: Double { records.first?.voiceBalance ?? 0.5 }

    private func toggle() {
        if isRecording {
            Task { await session.stop() }
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        session.reset()
        await session.start(.init(engine: engine, settings: settings, context: modelContext, errors: errors))
    }

    /// Encoding and saving follow the engine's own progress, which covers the first 95 %.
    static func overall(_ progress: AnalysisProgress?) -> Double {
        guard let progress else { return 0.02 }
        return 0.02 + 0.93 * progress.overallFraction
    }

    static func stageLabel(_ progress: AnalysisProgress?) -> LocalizedStringResource {
        guard let progress else { return .analysisPhaseModels }
        return switch progress.stage {
        case .detectingSpeech: .progressDetectingSpeech
        case .analyzingPitch: .progressAnalyzingF0
        case .extractingFeatures: .progressExtractingVfp
        case .scoringTimbre: .progressClassifyingVfp
        case .scoringFlow: .progressScoringFlow
        case .calculatingScores: .progressCalculatingScores
        case .measuringVoice: .voiceHealthStageExtracting
        case .scoringVoiceQuality: .voiceQualityStageScoring
        case .completed: progress.kind == .voiceQuality ? .voiceQualityStageCompleted : .progressCompleted
        }
    }
}

/// A soft wash of the orb's colors behind immersive screens.
struct AmbientBackground: View {
    var balance: Double
    @Environment(\.theme) private var theme

    var body: some View {
        let color = theme.balance(balance)
        LinearGradient(colors: [color.opacity(0.18), .clear, color.opacity(0.10)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
