import EuphonaKit
import SwiftData
import SwiftUI

struct PitchView: View {
    @Environment(\.theme) private var theme
    /// A lesson's target; on its own the tool shows the voice goal's typical band when that is on.
    var target: PitchTarget?
    @Environment(AppSettings.self) private var settings
    @Environment(VoiceEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @State private var monitor: PitchMonitor

    /// A lesson passes its own monitor to read the try's measurements.
    init(target: PitchTarget? = nil, monitor: PitchMonitor = PitchMonitor()) {
        self.target = target
        _monitor = State(initialValue: monitor)
    }

    var body: some View {
        let low = Double(settings.analyzer.minF0Hz), high = Double(settings.analyzer.maxF0Hz)
        InstrumentPanel(title: .pitchTitle, reading: reading) {
            if low >= high {
                ContentUnavailableView { Text(.pitchRangeInvalid) }
            } else if let failure = monitor.failure {
                CaptureFailureView(failure: failure, title: .pitchTitle, retry: toggle)
            } else {
                PitchChart(monitor: monitor, low: low, high: high, style: settings.pitchChartStyle,
                           gapSeconds: Double(settings.gapThresholdMs) / 1000, target: shownTarget)
            }
        } controls: {
            if monitor.state != .idle {
                InstrumentSideButton(symbol: "gobackward", label: .pitchRewind3) {
                    monitor.rewind(engine: engine, settings: settings)
                }
            }
            InstrumentPrimaryButton(title: toggleTitle, symbol: isLive ? "pause.fill" : "waveform", action: toggle)
        }
        .overlay(alignment: .bottom) {
            if let playhead = monitor.replay.playhead, let tail = monitor.replay.tail {
                ReplayBadge(text: Text(monitor.replay.reachedLastPage ? LocalizedStringResource.pitchLastPage
                                                                       : .pitchRewindSeconds(Float(tail - playhead))))
                    .padding(.bottom, 84)
            }
        }
        .toolbar {
            if target == nil {
                ToolbarItem(placement: .primaryAction) {
                    @Bindable var settings = settings
                    Toggle(isOn: $settings.showsPitchTarget) {
                        Label { Text(.pitchTargetToggle) } icon: { Image(systemName: "target") }
                    }
                    .help(Text(.pitchTargetToggle))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: monitor.state)
        .onDisappear { monitor.finish(context: modelContext) }
        .sensoryFeedback(.selection, trigger: monitor.replay.reachedLastPage) { !$0 && $1 }
        .accessibilityLabel(monitor.currentHz.map { Text(.pitchAccessibilityCurrent(Float($0))) } ?? Text(.pitchAccessibilityWaiting))
    }

    private var shownTarget: PitchTarget? {
        target ?? (settings.showsPitchTarget ? .typicalBand(for: settings.voiceGoal) : nil)
    }

    private var reading: InstrumentReading {
        let hz = monitor.currentHz
        let note: Text? = hz.flatMap(NoteName.of(hz:)).map { name in
            guard let target = shownTarget, let share = monitor.share(on: target) else { return Text(verbatim: name) }
            return Text(.pitchOnTarget(name, (share * 100).percent(decimals: 0)))
        }
        let status: Text = note
            ?? Text(monitor.state == .preparing ? LocalizedStringResource.pitchPreparing
                    : monitor.state == .idle ? .pitchReferenceSubtitle : .pitchNoVoice)
        return InstrumentReading(value: hz.map { "\(Int($0.rounded()))" }, unit: "Hz", symbol: "waveform",
                                 color: hz.map { theme.pitch($0) } ?? .primary, detail: status)
    }

    private var isLive: Bool { monitor.state == .running || monitor.state == .preparing }

    private var toggleTitle: LocalizedStringResource {
        switch monitor.state {
        case .idle: .pitchStartMonitoring
        case .running, .preparing: .pitchStopMonitoring
        case .paused: .pitchResumeAnalysis
        }
    }

    private func toggle() {
        if isLive { monitor.pause() } else { Task { await monitor.start(engine: engine, settings: settings) } }
    }
}
