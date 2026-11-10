import EuphonaKit
import SwiftData
import SwiftUI

/// Everything a finished analysis shows; also used for records from history.
struct ResultContent {
    var result: EuphonaResult
    /// The saved record, for screens opened from the result (nil if saving failed).
    var recordID: PersistentIdentifier?
    var audioData: Data?
    var waveform: [Float]
    var timeline: ScoreTimeline?
    var segmentScores: [SegmentScore]
    var previousScore: Double?
    var previousMetrics: PreviousMetrics?
    var previousRecording: PreviousRecording?

    init(_ outcome: AnalysisOutcome) {
        result = outcome.result
        recordID = outcome.recordID
        audioData = outcome.audioData
        waveform = outcome.waveform
        timeline = outcome.timeline
        segmentScores = outcome.segmentScores
        previousScore = outcome.previousScore
        previousMetrics = outcome.previousMetrics
        previousRecording = outcome.previousRecording
    }

    /// `previous` is what the record is compared with (`HistoryStore.previousAnalysis`).
    init(record: AnalysisRecord, result: EuphonaResult, previous: AnalysisRecord?) {
        self.result = result
        recordID = record.persistentModelID
        audioData = record.audio
        waveform = []
        timeline = result.inputSeconds > 0 ? ScoreTimeline(result: result, duration: result.inputSeconds) : nil
        segmentScores = SegmentScore.segments(of: result)
        previousScore = previous?.finalScore
        previousMetrics = previous.map(PreviousMetrics.init)
        previousRecording = PreviousRecording(previous)
    }
}

struct ResultView: View {
    @Environment(\.openCoach) private var openCoach
    var content: ResultContent
    /// Count the score up with sound (once, for a new result).
    var animate: Bool

    @State private var playback: RecordingPlayback?
    @State private var waveform: [Float] = []
    /// The list recreates the hero row when it scrolls back into view; the reveal plays only once.
    @State private var revealed = false

    private var result: EuphonaResult { content.result }
    private var breakdown: ScoreBreakdown { result.composite }

    var body: some View {
        // A grouped form: inset cards on iPhone and iPad, System Settings-style groups on Mac, where a
        // plain list drew a separator under every row and left links clickable only on their text.
        Form {
            #if os(macOS)
            // Mac forms draw a card behind every row and ignore a clear row background; a section header
            // sits on the page itself.
            Section {} header: { hero.textCase(nil) }
            #else
            Section { hero }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listSectionSpacing(0)
            #endif

            verdict

            if let playback {
                Section {
                    RecordingTimeline(waveform: waveform, trace: PitchTrace(result: result),
                                      segments: content.segmentScores, timeline: content.timeline, playback: playback)
                        .padding(.vertical, 8)
                }
            }

            Section {
                MetricsCard(result: result, previous: content.previousMetrics, focus: breakdown.bottleneck)
            } header: {
                Text(.scoreMetricsToggle)
            } footer: {
                Text(result.scoreProfile == .masculinization ? LocalizedStringResource.scoreF0RangeNoteMasculine : .scoreF0RangeNote)
            }

            if let previous = content.previousRecording, let playback, playback.isAvailable {
                Section {
                    ListenBack(current: playback, previous: previous)
                } header: { Text(.listenBackTitle) } footer: { Text(.listenBackFooter) }
            }

            suggestion
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .readableContentWidth(720)
        .background {
            AmbientBackground(balance: result.voiceBalance)
                .background(Color.groupedBackground)
                .ignoresSafeArea()
        }
        .task(id: result.composite.finalScore) {
            playback = RecordingPlayback(data: content.audioData, duration: result.inputSeconds)
            waveform = content.waveform.isEmpty ? await Self.waveform(of: content.audioData) : content.waveform
        }
        .onDisappear { playback?.stop() }
    }

    private var hero: some View {
        ScoreHero(score: result.composite.finalScore, previousScore: content.previousScore,
                  balance: result.voiceBalance, animate: animate && !revealed) { revealed = true }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    @ViewBuilder private var verdict: some View {
        let done = breakdown.bottleneck == nil
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(breakdown.focusTitle).font(.headline)
                    Text(breakdown.focusGuidance).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: done ? "checkmark.seal.fill" : "arrow.up.forward.circle.fill")
                    .foregroundStyle(done ? Tokens.success : Color.accentColor)
                    .font(.title2)
            }
            .padding(.vertical, 4)
            if let recordID = content.recordID {
                NavigationLink(value: Route.rules(record: recordID)) {
                    Label { Text(.scoreViewRules) } icon: { Image(systemName: "function") }
                }
            }
        }
    }

    /// Where to practise what the result points at; only where the Coach tab is reachable.
    @ViewBuilder private var suggestion: some View {
        if let openCoach {
            Section {
                Button { openCoach() } label: {
                    Label { Text(.coachPracticeWithCoach) } icon: { Image(systemName: AppTab.coach.symbol) }
                }
            }
        }
    }

    /// History stores AAC; derive the bars from it once.
    private static func waveform(of data: Data?) async -> [Float] {
        guard let data else { return [] }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(AudioEncoder.fileExtension)")
        guard (try? data.write(to: url)) != nil else { return [] }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let audio = try? await AudioFileReader.read(url) else { return [] }
        return await (try? offMain { Waveform.peaks(of: audio) }) ?? []
    }
}

/// Timbre, pitch, flow and ease with a bar each, the weakest one flagged, and the change since last time.
struct MetricsCard: View {
    var result: EuphonaResult
    var previous: PreviousMetrics?
    var focus: ScoreMetric?

    var body: some View {
        let masculine = result.scoreProfile == .masculinization
        let standard = masculine ? 100 - result.timbre.score : result.timbre.score
        let previousStandard = previous.map { masculine ? 100 - $0.timbreScore : $0.timbreScore }
        VStack(alignment: .leading, spacing: 18) {
            row(.timbre, value: standard.formatted(decimals: 1), progress: standard, delta: previousStandard.map { standard - $0 })
            if let hz = result.f0.speakingHz {
                row(.f0, value: hz.hertz(), progress: Scoring.pitchProgress(hz, goal: result.scoreProfile),
                    delta: previous?.speakingF0Hz.map { hz - $0 }, format: .hertz)
            } else {
                row(.f0, valueText: Text(.scoreValueNotDetected), progress: 0, delta: nil)
            }
            row(.flow, value: result.flow.score.formatted(decimals: 1), progress: result.flow.score,
                delta: previous.map { result.flow.score - $0.flowScore })
            row(.ease, value: result.ease.formatted(decimals: 1), progress: result.ease,
                delta: previous.map { result.ease - $0.easeScore })
        }
        .padding(.vertical, 8)
    }

    private func row(_ metric: ScoreMetric, value: String, progress: Double, delta: Double?, format: MetricFormat = .score) -> some View {
        row(metric, valueText: Text(verbatim: value), progress: progress, delta: delta, format: format)
    }

    private func row(_ metric: ScoreMetric, valueText: Text, progress: Double, delta: Double?, format: MetricFormat = .score) -> some View {
        let color = Tokens.scoreColor(progress)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label { Text(metric.title) } icon: { Image(systemName: metric.symbol).foregroundStyle(color) }
                    .font(.body)
                if focus == metric {
                    Text(.scoreLowest)
                        .font(.caption2.bold())
                        .foregroundStyle(color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(color.opacity(0.16), in: .capsule)
                }
                Spacer()
                if let delta, abs(delta) > format.threshold {
                    Text(verbatim: format.change(delta))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                valueText.font(.headline.monospacedDigit())
            }
            Gauge(value: min(max(progress, 0), 100), in: 0...100) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(color)
        }
    }
}
