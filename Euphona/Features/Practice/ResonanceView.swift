import Charts
import Observation
import EuphonaKit
import SwiftUI

/// Live resonance: F1 and F2 of every voiced 32 ms frame, read as the median of the last ~0.3 s.
@MainActor @Observable
final class ResonanceMonitor {
    /// Frames in the trail and the reading's median.
    static let trailLength = 30
    static let readingFrames = 9

    let input = LiveInput()
    private(set) var trail: [FormantFrame] = []
    private(set) var heard = 0.0
    @ObservationIgnored private let stream = RealtimeFormantStream()
    /// Every reading this session, for lessons.
    @ObservationIgnored private(set) var brightnessHistory: [Double] = []

    var current: Formants? {
        guard let last = trail.last, heard - last.timestamp < 0.4 else { return nil }
        let recent = trail.suffix(Self.readingFrames)
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        return Formants(f1: median(recent.map(\.formants.f1)), f2: median(recent.map(\.formants.f2)))
    }

    func start() async {
        await input.start(mode: .measurement, prepare: {
            stream.reset()
            trail = []
            heard = 0
            brightnessHistory = []
        }, chunk: { [weak self] samples in
            guard let self else { return }
            self.heard += Double(samples.count) / Double(RealtimeFormantStream.sampleRate)
            let stream = self.stream
            let frames = (try? await offMain { stream.process(samples) }) ?? []
            guard !frames.isEmpty else { return }
            self.trail = Array((self.trail + frames).suffix(Self.trailLength))
            if let current = self.current { self.brightnessHistory.append(VowelNorms.brightness(current).brightness) }
        })
    }

    func stop() { input.stop() }
}

struct ResonanceView: View {
    @Environment(\.theme) private var theme
    @State private var monitor: ResonanceMonitor

    init(monitor: ResonanceMonitor = ResonanceMonitor()) {
        _monitor = State(initialValue: monitor)
    }

    var body: some View {
        InstrumentPanel(title: .resonanceTitle, reading: reading) {
            if let failure = monitor.input.failure {
                CaptureFailureView(failure: failure, title: .resonanceTitle, retry: toggle)
            } else {
                VowelChart(trail: monitor.trail, current: monitor.current)
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
        guard let current = monitor.current else {
            let detail: LocalizedStringResource = monitor.input.state == .idle ? .resonanceSubtitle : .resonanceHoldVowel
            return InstrumentReading(value: nil, symbol: "circle.hexagongrid", detail: Text(detail))
        }
        let (vowel, brightness) = VowelNorms.brightness(current)
        return InstrumentReading(
            value: brightness.formatted(decimals: 0), symbol: "circle.hexagongrid",
            color: theme.balance(brightness / 100),
            detail: Text(.resonanceReading(vowel.symbol, current.f1.hertz(), current.f2.hertz())))
    }

    private func toggle() {
        if monitor.input.isRunning { monitor.stop() } else { Task { await monitor.start() } }
    }
}

/// F1 against F2 the way phoneticians draw vowels: front vowels on the left, open vowels at the
/// bottom. Each landmark vowel is a blue (typical masculine) and a pink (typical feminine) dot; the
/// voice is a fading trail with a bright head.
struct VowelChart: View {
    @Environment(\.theme) private var theme
    var trail: [FormantFrame]
    var current: Formants?


    var body: some View {
        Chart {
            ForEach(VowelNorms.vowels) { vowel in
                LineMark(x: .value("F2", -vowel.masculine.f2), y: .value("F1", -vowel.masculine.f1), series: .value("Vowel", vowel.symbol))
                    .foregroundStyle(Color.gray.opacity(0.3))
                LineMark(x: .value("F2", -vowel.feminine.f2), y: .value("F1", -vowel.feminine.f1), series: .value("Vowel", vowel.symbol))
                    .foregroundStyle(Color.gray.opacity(0.3))
                PointMark(x: .value("F2", -vowel.masculine.f2), y: .value("F1", -vowel.masculine.f1))
                    .foregroundStyle(theme.deepBlue.opacity(0.7))
                    .symbolSize(60)
                PointMark(x: .value("F2", -vowel.feminine.f2), y: .value("F1", -vowel.feminine.f1))
                    .foregroundStyle(theme.deepPink.opacity(0.7))
                    .symbolSize(60)
                    .annotation(position: .topLeading, spacing: 2) {
                        Text(verbatim: vowel.symbol).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    }
            }
            ForEach(Array(trail.enumerated()), id: \.offset) { index, frame in
                PointMark(x: .value("F2", -frame.formants.f2), y: .value("F1", -frame.formants.f1))
                    .foregroundStyle(.tint.opacity(Double(index + 1) / Double(trail.count) * 0.5))
                    .symbolSize(30)
            }
            if let current {
                PointMark(x: .value("F2", -current.f2), y: .value("F1", -current.f1))
                    .foregroundStyle(.tint)
                    .symbolSize(260)
            }
        }
        .chartXScale(domain: -VowelNorms.f2Range.upperBound...(-VowelNorms.f2Range.lowerBound))
        .chartYScale(domain: -VowelNorms.f1Range.upperBound...(-VowelNorms.f1Range.lowerBound))
        .chartXAxis {
            AxisMarks(values: [-3000, -2000, -1000]) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(verbatim: (-v).formatted(decimals: 0)) } }
            }
        }
        .chartYAxis {
            AxisMarks(values: [-1000, -600, -200]) { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(verbatim: (-v).formatted(decimals: 0)) } }
            }
        }
        .chartXAxisLabel(position: .bottom, alignment: .center) { Text(verbatim: "F2 (\(UnitFrequency.hertz.symbol))") }
        .chartYAxisLabel(position: .leading, alignment: .center) { Text(verbatim: "F1 (\(UnitFrequency.hertz.symbol))") }
        .animation(.smooth(duration: 0.15), value: current)
        .accessibilityHidden(true)
    }
}
