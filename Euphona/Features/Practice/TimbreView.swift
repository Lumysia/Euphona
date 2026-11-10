import Charts
import Observation
import EuphonaKit
import SwiftUI

/// Live timbre: the timbre model on the last 1.5 s of speech, twice a second.
@MainActor @Observable
final class TimbreMonitor {
    static let historySeconds = 30.0
    /// Frames averaged for the reading, so it moves with the voice but doesn't jitter.
    static let smoothing = 3

    let input = LiveInput()
    /// Feminine timbre, 0 (masculine) to 100 (feminine), newest last.
    private(set) var frames: [TimbreFrame] = []
    /// Seconds of audio heard since starting, on the frames' timeline.
    private(set) var heard = 0.0
    @ObservationIgnored private var stream: RealtimeTimbreStream?

    /// The smoothed current score, or nil while there is no recent speech.
    var current: Double? {
        guard let last = frames.last, heard - last.timestamp < 1.5 else { return nil }
        let recent = frames.suffix(Self.smoothing)
        return recent.map(\.score).reduce(0, +) / Double(recent.count)
    }

    func start(engine: VoiceEngine, settings: AppSettings) async {
        await input.start(mode: .voice, prepare: {
            if stream == nil {
                let analyzer = try await engine.analyzer(for: settings.analyzer)
                stream = RealtimeTimbreStream(analyzer: analyzer)
            }
            stream?.reset()
            frames = []
            heard = 0
        }, chunk: { [weak self] samples in
            guard let self else { return }
            self.heard += Double(samples.count) / Double(RealtimeTimbreStream.sampleRate)
            guard let stream = self.stream,
                  let frame = try? await offMain({ try stream.process(samples) }) else { return }
            self.frames.append(frame)
            self.frames.removeAll { $0.timestamp < frame.timestamp - Self.historySeconds }
        })
    }

    func stop() { input.stop() }

    /// Share of scored time inside `range`, for lessons.
    func share(in range: ClosedRange<Double>) -> Double? {
        guard !frames.isEmpty else { return nil }
        return Double(frames.filter { range.contains($0.score) }.count) / Double(frames.count)
    }
}

struct TimbreView: View {
    /// A goal band on the goal-aligned scale (0–100, higher is closer to the voice goal).
    var target: ClosedRange<Double>?
    @Environment(AppSettings.self) private var settings
    @Environment(VoiceEngine.self) private var engine
    @State private var monitor: TimbreMonitor

    init(target: ClosedRange<Double>? = nil, monitor: TimbreMonitor = TimbreMonitor()) {
        self.target = target
        _monitor = State(initialValue: monitor)
    }

    private var feminineGoal: Bool { settings.voiceGoal == .feminine }
    private func aligned(_ score: Double) -> Double { feminineGoal ? score : 100 - score }

    var body: some View {
        InstrumentPanel(title: .timbreTitle, reading: reading) {
            if let failure = monitor.input.failure {
                CaptureFailureView(failure: failure, title: .timbreTitle, retry: toggle)
            } else {
                TimbreTrend(frames: monitor.frames, end: monitor.heard, aligned: aligned, target: target)
                    .padding(20)
            }
        } controls: {
            InstrumentPrimaryButton(title: monitor.input.isRunning ? .pitchStopMonitoring : .pitchStartMonitoring,
                                    symbol: monitor.input.isRunning ? "pause.fill" : "waveform", action: toggle)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: monitor.input.state)
        .onDisappear { monitor.stop() }
    }

    private var reading: InstrumentReading {
        let value = monitor.current.map(aligned)
        let detail: LocalizedStringResource = switch monitor.input.state {
        case .idle: .timbreSubtitle
        case .preparing: .timbrePreparing
        case .running: value == nil ? .timbreListening : (feminineGoal ? .timbreFeminineScale : .timbreMasculineScale)
        }
        return InstrumentReading(value: value.map { $0.formatted(decimals: 0) }, symbol: "person.wave.2",
                                 color: value.map(Tokens.scoreColor) ?? .primary, detail: Text(detail))
    }

    private func toggle() {
        if monitor.input.isRunning { monitor.stop() } else { Task { await monitor.start(engine: engine, settings: settings) } }
    }
}

/// The last 30 s of timbre on the goal-aligned scale, filling the card, with the pass line at 50 and
/// the lesson's band.
private struct TimbreTrend: View {
    var frames: [TimbreFrame]
    var end: Double
    var aligned: (Double) -> Double
    var target: ClosedRange<Double>?

    var body: some View {
        let end = max(end, TimbreMonitor.historySeconds)
        Chart {
            if let target {
                RectangleMark(xStart: .value("Start", end - TimbreMonitor.historySeconds), xEnd: .value("End", end),
                              yStart: .value("Low", target.lowerBound), yEnd: .value("High", target.upperBound))
                    .foregroundStyle(.tint.opacity(0.12))
            }
            RuleMark(y: .value("Pass", 50))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(frames, id: \.timestamp) { frame in
                LineMark(x: .value("Time", frame.timestamp), y: .value("Timbre", aligned(frame.score)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .chartXScale(domain: (end - TimbreMonitor.historySeconds)...end)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(values: [0, 50, 100]) }
        .accessibilityHidden(true)
    }
}
