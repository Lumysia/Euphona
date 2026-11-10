import EuphonaKit
import SwiftUI

/// The listening experience shared by voice analysis and voice health: the orb breathes with the voice,
/// a ring of 72 amplitude bars surrounds it, and a thin ring fills with valid speech (or, while
/// analyzing, with progress).
struct CaptureStage: View {
    enum Phase: Equatable {
        case idle
        case recording(elapsed: Double, speech: Double)
        case analyzing(progress: Double, stage: LocalizedStringResource)
    }

    static let waveformBars = 72

    var phase: Phase
    var requiredSpeechSeconds: Double
    var amplitudes: [Float]
    /// The orb's resting balance, e.g. the latest score.
    var balance: Double
    var idleTitle: LocalizedStringResource
    var idleSubtitle: LocalizedStringResource
    /// The waveform's outer size on iPhone; the rings and orb scale with it, and larger windows scale
    /// all of it by `orbScale`.
    var baseDiameter: CGFloat = 300
    @Environment(\.orbScale) private var orbScale

    private var diameter: CGFloat { baseDiameter * orbScale }

    private var isRecording: Bool { if case .recording = phase { true } else { false } }

    private var ringProgress: Double {
        switch phase {
        case .idle: 0
        case .recording(_, let speech): min(max(speech / max(requiredSpeechSeconds, 0.01), 0), 1)
        case .analyzing(let progress, _): progress
        }
    }

    var body: some View {
        VStack(spacing: diameter * 0.07) {
            ZStack {
                RadialWaveform(amplitudes: isRecording ? amplitudes : [])
                    .frame(width: diameter, height: diameter)
                    .opacity(isRecording ? 1 : 0)
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: 4)
                    .frame(width: diameter * 0.79, height: diameter * 0.79)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter * 0.79, height: diameter * 0.79)
                    .animation(.spring(response: 0.6, dampingFraction: 0.86), value: ringProgress)
                VoiceOrb(balance: balance, energy: isRecording ? Double(amplitudes.last ?? 0) : 0, activity: activity, halo: false)
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
                    .glassBubble(diameter: diameter * 0.6, balance: balance)
            }
            .frame(height: diameter)
            status
                .frame(minHeight: 76, alignment: .top)
        }
        .animation(.smooth(duration: 0.35), value: isRecording)
        .sensoryFeedback(.start, trigger: isRecording) { !$0 && $1 }
        .sensoryFeedback(.success, trigger: isRecording && ringProgress >= 1) { !$0 && $1 }
    }

    private var activity: VoiceOrb.Activity {
        switch phase {
        case .idle: .resting
        case .recording: .listening
        case .analyzing: .thinking
        }
    }

    @ViewBuilder private var status: some View {
        VStack(spacing: 6) {
            switch phase {
            case .recording(let elapsed, let speech):
                Text(verbatim: elapsed.clock)
                    .scaledFont(size: 44, weight: .heavy, design: .rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(.voiceCaptureProgress(Float(speech), Float(requiredSpeechSeconds)))
                    .font(.headline.weight(ringProgress >= 1 ? .bold : .medium))
                    .foregroundStyle(ringProgress >= 1 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
            case .idle:
                Text(idleTitle).font(.title2.bold())
                Text(idleSubtitle).font(.subheadline).foregroundStyle(.secondary)
            case .analyzing(_, let stage):
                Text(.analysisPhaseInference).font(.title2.bold())
                Text(stage).font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .id(String(localized: stage))
            }
        }
        .multilineTextAlignment(.center)
        .animation(.smooth, value: phase)
    }

}

/// The record control: a round glass button that flows into a "Stop and analyze" capsule while
/// recording and back again, one glass shape morphing between the two.
struct CaptureButton: View {
    var isRecording: Bool
    var isEnabled: Bool
    var action: () -> Void
    @Environment(AppSettings.self) private var settings
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .scaledFont(size: isRecording ? 22 : 30, weight: .semibold, relativeTo: .title)
                        .contentTransition(.symbolEffect(.replace))
                    if isRecording {
                        Text(.stopAndAnalyze)
                            .font(.headline)
                            .fixedSize()
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, isRecording ? 28 : 0)
                .frame(minWidth: 84, minHeight: 84)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(isRecording ? .red : settings.palette.tint).interactive(), in: .capsule)
            .glassEffectID("record", in: glass)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: isRecording)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
        .accessibilityLabel(isRecording ? Text(.stopAndAnalyze) : Text(.startRecording))
        .keyboardShortcut(.space, modifiers: [])
    }
}

/// The newest 72 smoothed amplitudes as bars radiating from the orb.
struct RadialWaveform: View {
    var amplitudes: [Float]

    var body: some View {
        Canvas { context, size in
            let bars = CaptureStage.waveformBars
            let values = amplitudes.suffix(bars)
            guard !values.isEmpty else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let inner = min(size.width, size.height) / 2 * 0.82
            let reach = min(size.width, size.height) / 2 - inner
            for index in 0..<bars {
                let value = values[values.startIndex + min(index * values.count / bars, values.count - 1)]
                let amplitude = CGFloat(min(max(value, 0), 1))
                let angle = Double(index) / Double(bars) * 2 * .pi - .pi / 2
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                var bar = Path()
                bar.move(to: CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner))
                let outer = inner + 3 + reach * amplitude
                bar.addLine(to: CGPoint(x: center.x + direction.x * outer, y: center.y + direction.y * outer))
                context.stroke(bar, with: .style(.tint.opacity(0.25 + amplitude * 0.6)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}
