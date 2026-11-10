import EuphonaKit
import SwiftData
import SwiftUI

/// Voice Quality: about 20 s of speech, checked for clipping, noise and too little voice, then an
/// estimate of how the voice sounds to listeners, shown next to how it feels to the person.
struct VoiceQualityView: View {
    static let maximumSeconds = 45.0
    /// Detected speech, pauses excluded: about 20 s of talking. Analysis starts by itself once reached.
    static let minimumSpeechSeconds = 15.0

    enum State { case ready, recording, analyzing(AnalysisProgress?), finished(VoiceQualityEstimate), failed(CaptureFailure) }

    @Environment(AppSettings.self) private var settings
    @Environment(VoiceEngine.self) private var engine
    @State private var capture = SpeechCapture(maximumSeconds: maximumSeconds, mode: .measurement)
    @State private var state: State = .ready
    /// Bumped when the page closes, so a recording or analysis still running is dropped.
    @State private var generation = 0

    var body: some View {
        InstrumentPanel(title: .voiceQualityTitle, reading: reading) {
            switch state {
            case .finished(let estimate):
                if estimate.check.issues.isEmpty {
                    VoiceQualityResult(estimate: estimate)
                } else {
                    RecordingIssues(issues: estimate.check.issues)
                }
            case .failed(let failure):
                CaptureFailureView(failure: failure, title: .voiceQualityFailed, retry: toggle)
            case .analyzing(let progress):
                ProgressView(value: progress?.overallFraction ?? 0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)
            default:
                LiveLevel(amplitudes: capture.amplitudes, speech: capture.speechSeconds,
                          required: Self.minimumSpeechSeconds, isRecording: capture.isRecording)
            }
        } controls: {
            InstrumentPrimaryButton(title: buttonTitle, symbol: buttonSymbol, action: toggle)
                .tint(capture.isRecording ? .red : nil)
                .disabled(isAnalyzing)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: capture.isRecording)
        .sensoryFeedback(.impact(weight: .medium), trigger: capture.isRecording)
        .sensoryFeedback(.success, trigger: isFinished)
        .onChange(of: capture.speechSeconds >= Self.minimumSpeechSeconds) { _, enough in
            if enough, case .recording = state { Task { await stop() } }
        }
        .onDisappear {
            generation += 1
            if case .recording = state { Task { _ = await capture.stop() } }
            state = .ready
        }
    }

    private var reading: InstrumentReading {
        switch state {
        case .finished(let estimate) where estimate.check.issues.isEmpty:
            return InstrumentReading(value: estimate.score.formatted(decimals: 0), symbol: "waveform.and.person.filled",
                                     color: estimate.suggestsRest ? Tokens.warning : Tokens.success,
                                     detail: Text(estimate.suggestsRest ? LocalizedStringResource.voiceQualityResultRest : .voiceQualityResultClear))
        case .finished:
            return InstrumentReading(value: nil, symbol: "exclamationmark.triangle", detail: Text(.voiceQualityRecordingUnsuitable))
        case .analyzing(let progress):
            return InstrumentReading(value: nil, symbol: "waveform.badge.magnifyingglass", detail: Text(AnalysisView.stageLabel(progress)))
        case .recording:
            let enough = capture.speechSeconds >= Self.minimumSpeechSeconds
            return InstrumentReading(value: capture.speechSeconds.formatted(decimals: 0), unit: "s", symbol: "mic",
                                     detail: Text(enough ? LocalizedStringResource.voiceQualityStop : .voiceQualityKeepTalking))
        default:
            return InstrumentReading(value: nil, symbol: "waveform.and.person.filled", detail: Text(.voiceQualitySubtitle))
        }
    }

    private var isFinished: Bool { if case .finished = state { true } else { false } }

    private var buttonTitle: LocalizedStringResource {
        switch state {
        case .recording: .stopAndAnalyze
        case .finished, .failed: .voiceQualityRecordAgain
        default: .startRecording
        }
    }

    private var buttonSymbol: String {
        switch state {
        case .recording: "stop.fill"
        case .finished, .failed: "arrow.clockwise"
        default: "mic.fill"
        }
    }

    private var isAnalyzing: Bool { if case .analyzing = state { true } else { false } }

    private func toggle() {
        Task {
            switch state {
            case .recording: await stop()
            case .finished, .failed: state = .ready; await start()
            default: await start()
            }
        }
    }

    private func start() async {
        guard await MicrophoneCapture.requestPermission() else { state = .failed(.microphoneDenied); return }
        do {
            let analyzer = try await engine.analyzer(for: settings.analyzer)
            try capture.start(analyzer: analyzer) { Task { await stop() } }
            state = .recording
        } catch {
            state = .failed(.couldNotStart)
        }
    }

    private func stop() async {
        guard case .recording = state else { return }
        state = .analyzing(nil)
        let generation = generation
        let audio = await capture.stop()
        guard generation == self.generation else { return }
        guard capture.speechSeconds >= Self.minimumSpeechSeconds else {
            state = .failed(.tooLittleSpeech)
            return
        }
        do {
            let analyzer = try await engine.analyzer(for: settings.analyzer)
            let estimate = try await offMain {
                try analyzer.voiceQuality(audio) { progress in
                    Task { @MainActor in state = .analyzing(progress) }
                }
            }
            guard generation == self.generation else { return }
            state = .finished(estimate)
        } catch let error as AnalysisError where error.kind == .noSpeech {
            guard generation == self.generation else { return }
            state = .failed(.tooLittleSpeech)
        } catch {
            guard generation == self.generation else { return }
            state = .failed(.analysisFailed)
        }
    }
}

/// The voice while recording: recent loudness as bars, and how much usable speech there is so far.
private struct LiveLevel: View {
    var amplitudes: [Float]
    var speech: Double
    var required: Double
    var isRecording: Bool

    var body: some View {
        VStack(spacing: 20) {
            Canvas { context, size in
                let bars = 48
                let recent = Array(repeating: 0, count: max(0, bars - amplitudes.count)) + amplitudes.suffix(bars)
                let width = size.width / CGFloat(bars)
                for (index, value) in recent.enumerated() {
                    let height = max(6, CGFloat(min(value, 1)) * size.height)
                    let rect = CGRect(x: CGFloat(index) * width + width * 0.2,
                                      y: (size.height - height) / 2, width: width * 0.6, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: width * 0.3),
                                 with: isRecording ? .style(.tint) : .style(.quaternary))
                }
            }
            .frame(height: 120)
            VStack(spacing: 6) {
                ProgressView(value: min(speech / required, 1)).progressViewStyle(.linear)
                Text(.voiceQualitySpeechProgress(Float(min(speech, required)), Float(required)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 280)
        }
        .padding(24)
    }
}

/// The estimate beside the person's own comfort report, and the measures behind it.
private struct VoiceQualityResult: View {
    var estimate: VoiceQualityEstimate
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorCenter.self) private var errors
    @Query(sort: \VoiceCheckIn.date, order: .reverse) private var checkIns: [VoiceCheckIn]

    private var today: VoiceCheckIn? { checkIns.first { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(.voiceQualityComfortTitle).font(.headline)
                    ComfortPicker(comfort: Binding(get: { today?.comfort }, set: { record($0) }))
                    if today?.pain == true || (today?.comfort ?? 3) <= 1 || estimate.suggestsRest {
                        Label { Text(.voiceQualityRestAdvice) } icon: { Image(systemName: "leaf").foregroundStyle(Tokens.success) }
                            .font(.subheadline)
                    }
                }
                .padding(16)
                .background(Color.groupedBackground, in: .rect(cornerRadius: 18))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    tile(.voiceHealthMetricHnr, estimate.features.hnrDb, 1, "dB")
                    tile(.voiceHealthMetricCpps, estimate.features.cppsDb, 1, "dB")
                    tile(.voiceHealthMetricJitter, estimate.features.jitterLocal * 100, 2, "%")
                    tile(.voiceHealthMetricShimmer, estimate.features.shimmerLocal * 100, 1, "%")
                    tile(.voiceHealthMetricF0, estimate.features.f0Median, 0, "Hz")
                    tile(.voiceHealthMetricIntensity, estimate.features.intensityMedian, 0, "dB")
                }
                Text(.voiceQualityDisclaimer).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func record(_ comfort: Int?) {
        guard let comfort else { return }
        errors.attempt(.errorChangeFailed) {
            try HistoryStore(context: modelContext).addCheckIn(comfort: comfort, pain: today?.pain ?? false)
        }
    }

    private func tile(_ title: LocalizedStringResource, _ value: Double, _ decimals: Int, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value.isFinite ? value.formatted(decimals: decimals) : "--")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                Text(verbatim: unit).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.groupedBackground, in: .rect(cornerRadius: 18))
    }
}

/// Why the recording can't be judged, and what to change.
private struct RecordingIssues: View {
    var issues: [RecordingCheck.Issue]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(issues, id: \.self) { issue in
                Label { Text(issue.advice) } icon: { Image(systemName: issue.symbol).foregroundStyle(Tokens.warning) }
                    .font(.body)
            }
        }
        .padding(24)
        .frame(maxWidth: 480, maxHeight: .infinity)
    }
}

extension RecordingCheck.Issue {
    var advice: LocalizedStringResource {
        switch self {
        case .clipping: .voiceQualityIssueClipping
        case .noisy: .voiceQualityIssueNoisy
        case .tooLittleVoice: .voiceQualityIssueTooLittleVoice
        }
    }

    var symbol: String {
        switch self {
        case .clipping: "speaker.wave.3"
        case .noisy: "waveform.badge.exclamationmark"
        case .tooLittleVoice: "text.bubble"
        }
    }
}
