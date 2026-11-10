import EuphonaKit
import SwiftUI

/// A live spectrogram in a dark card, with the strongest frequency read out on top.
struct SpectrumView: View {
    @State private var monitor = SpectrumMonitor()
    static let gridHz: [Double] = [8000, 4000, 2000, 1000, 500, 250, 125]

    var body: some View {
        InstrumentPanel(title: .spectrumTitle, reading: reading, darkCard: true) {
            ZStack {
                if let failure = monitor.failure {
                    CaptureFailureView(failure: failure, title: .spectrumStartFailed, retry: toggle)
                }
                if let image = monitor.image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.medium)
                }
                grid
                if monitor.state != .idle && !monitor.hasSignal {
                    Text(monitor.state == .preparing ? LocalizedStringResource.spectrumPreparing : .spectrumNoSignal)
                        .font(.headline).foregroundStyle(Tokens.spectrumAxis)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(monitor.hasSignal ? Text(.spectrumAccessibilityActive(Float(SpectrumMonitor.windowSeconds)))
                                                  : Text(.spectrumAccessibilityEmpty))
        } controls: {
            if monitor.state != .idle {
                InstrumentSideButton(symbol: "gobackward.5", label: .spectrumRewind5) { monitor.rewind() }
            }
            InstrumentPrimaryButton(title: title, symbol: isLive ? "pause.fill" : "chart.bar.xaxis", action: toggle)
        }
        .overlay(alignment: .bottom) {
            if let playhead = monitor.replay.playhead, let tail = monitor.replay.tail {
                ReplayBadge(text: Text(monitor.replay.reachedLastPage ? LocalizedStringResource.spectrumLastPage
                                                                       : .spectrumRewindSeconds(Float(tail - playhead))))
                    .padding(.bottom, 84)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: monitor.state)
        .onDisappear { monitor.stop() }
    }

    private var reading: InstrumentReading {
        let hz = monitor.state == .idle ? nil : monitor.peakHz
        let detail: Text = hz.flatMap(NoteName.of(hz:)).map { Text(.spectrumPeak($0)) }
            ?? Text(monitor.state == .idle ? LocalizedStringResource.spectrumSubtitle : .spectrumNoSignal)
        return InstrumentReading(value: hz.map { "\(Int($0.rounded()))" }, unit: "Hz", symbol: "chart.bar.xaxis", detail: detail)
    }

    private var grid: some View {
        GeometryReader { proxy in
            ForEach(Self.gridHz, id: \.self) { hz in
                let y = proxy.size.height * (1 - CGFloat(log10(hz / 40) / log10(8000.0 / 40)))
                Rectangle().fill(.white.opacity(hz == 1000 ? 0.24 : 0.12)).frame(height: hz == 1000 ? 1.5 : 1)
                    .offset(y: y)
                Text(verbatim: hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Tokens.spectrumAxis)
                    .offset(x: 12, y: y - 16)
            }
        }
        .allowsHitTesting(false)
    }

    private var isLive: Bool { monitor.state == .running || monitor.state == .preparing }

    private var title: LocalizedStringResource {
        switch monitor.state {
        case .idle: .spectrumStartMonitoring
        case .running, .preparing: .spectrumPause
        case .paused: .spectrumResumeAnalysis
        }
    }

    private func toggle() {
        if isLive { monitor.pause() } else { Task { await monitor.start() } }
    }
}
