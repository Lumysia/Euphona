import AVFAudio
import Observation
import EuphonaKit
import SwiftUI

/// Plays one recording. While it plays, `position` follows the player; views that show it redraw
/// with the display (`TimelineView`), so nothing polls.
@MainActor @Observable
final class RecordingPlayback: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    let duration: Double
    @ObservationIgnored private let player: AVAudioPlayer?
    /// The position while paused.
    private var resting: Double = 0

    init(data: Data?, duration: Double) {
        player = data.flatMap { try? AVAudioPlayer(data: $0) }
        // The result's window times refer to the analyzed input, so the timeline uses its length.
        self.duration = duration
        super.init()
        player?.delegate = self
        player?.prepareToPlay()
    }

    var isAvailable: Bool { player != nil }

    var position: Double {
        guard isPlaying, let player else { return resting }
        return min(player.currentTime, duration)
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            resting = position
            player.pause()
            isPlaying = false
            return
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        if resting >= duration - 0.1 { resting = 0 }
        player.currentTime = resting
        player.play()
        isPlaying = true
    }

    func seek(to seconds: Double) {
        resting = min(max(seconds, 0), duration)
        player?.currentTime = resting
    }

    func stop() {
        player?.stop()
        resting = position
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            resting = duration
        }
    }
}

/// The whole recording at a glance: waveform bars colored by each speech segment's score, the smoothed
/// pitch over them, and a playhead with the local metrics. Drag to scrub.
struct RecordingTimeline: View {
    @Environment(\.theme) private var theme
    var waveform: [Float]
    var trace: PitchTrace?
    var segments: [SegmentScore]
    var timeline: ScoreTimeline?
    var playback: RecordingPlayback

    static let height: CGFloat = 180

    var body: some View {
        TimelineView(.animation(paused: !playback.isPlaying)) { _ in content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            readout
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in drawWaveform(context, size) ; drawPitch(context, size) }
                    playhead(width: width)
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    playback.seek(to: Double(value.location.x / max(width, 1)) * playback.duration)
                })
            }
            .frame(height: Self.height)
            .accessibilityElement()
            .accessibilityLabel(Text(.playbackPosition))
            .accessibilityValue(Text(verbatim: playback.position.clock))
            .accessibilityAdjustableAction { direction in
                let step = max(playback.duration / 20, 1)
                switch direction {
                case .increment: playback.seek(to: min(playback.position + step, playback.duration))
                case .decrement: playback.seek(to: max(playback.position - step, 0))
                @unknown default: break
                }
            }
            HStack {
                Button(action: playback.toggle) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(!playback.isAvailable)
                .accessibilityLabel(playback.isPlaying ? Text(.pause) : Text(.play))
                .help(playback.isPlaying ? Text(.pause) : Text(.play))
                Spacer()
                Text(verbatim: "\(playback.position.clock) / \(playback.duration.clock)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readout: some View {
        let point = timeline?.point(at: playback.position)
        let hz = trace?.hz(at: playback.position)
        return HStack(spacing: 8) {
            chip(Text(.timelineStandardValue(point.map { "\(Int($0.timbreScore.rounded()))" } ?? "--")), color: .secondary)
            if let hz {
                chip(Text(.timelineF0Value(Float(hz))), color: theme.pitch(hz))
            }
            Spacer()
            if let score = point?.score {
                Text(verbatim: score.formatted(decimals: 0))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Tokens.scoreColor(score))
                    .contentTransition(.numericText(value: score))
            }
        }
        .animation(.snappy, value: point?.score)
    }

    private func chip(_ text: Text, color: Color) -> some View {
        text.font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.fill.tertiary, in: .capsule)
    }

    private func playhead(width: CGFloat) -> some View {
        let x = CGFloat(playback.position / max(playback.duration, 0.01)) * width
        return Capsule().fill(.tint).frame(width: 3, height: Self.height).offset(x: x - 1.5)
    }

    private func drawWaveform(_ context: GraphicsContext, _ size: CGSize) {
        guard !waveform.isEmpty else { return }
        let barSpacing: CGFloat = 3
        let bars = max(1, Int(size.width / barSpacing))
        let bandHeight = size.height * 0.55
        let center = size.height - bandHeight / 2
        for bar in 0..<bars {
            let lower = bar * waveform.count / bars
            let upper = max(lower + 1, (bar + 1) * waveform.count / bars)
            let peak = waveform[lower..<min(upper, waveform.count)].max() ?? 0
            let time = (Double(bar) + 0.5) / Double(bars) * playback.duration
            let score = segments.first { time >= $0.start && time < $0.end }?.score
            let half = score == nil ? 1.2 : max(2.5, CGFloat(sqrt(peak)) * bandHeight * 0.48)
            let x = (CGFloat(bar) + 0.5) * barSpacing
            var path = Path()
            path.move(to: CGPoint(x: x, y: center - half))
            path.addLine(to: CGPoint(x: x, y: center + half))
            let color = score.map(Tokens.scoreColor) ?? Tokens.neutralScore
            context.stroke(path, with: .color(color.opacity(score == nil ? 0.4 : 0.9)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func drawPitch(_ context: GraphicsContext, _ size: CGSize) {
        guard let trace, trace.points.count > 1 else { return }
        let ceiling = trace.displayMaximumHz
        func point(_ p: PitchTrace.Point) -> CGPoint {
            CGPoint(x: CGFloat(p.time / max(playback.duration, 0.01)) * size.width,
                    y: size.height * (1 - CGFloat(min(p.hz, ceiling) / ceiling)))
        }
        let lineY = size.height * (1 - CGFloat(Scoring.pitchMidpointHz / ceiling))
        var line = Path()
        line.move(to: CGPoint(x: 0, y: lineY))
        line.addLine(to: CGPoint(x: size.width, y: lineY))
        context.stroke(line, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        context.draw(Text(verbatim: Scoring.pitchMidpointHz.hertz()).font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: 2, y: lineY + 2), anchor: .topLeading)

        for (a, b) in zip(trace.points, trace.points.dropFirst()) where a.run == b.run {
            let start = point(a), end = point(b)
            let line = Scoring.pitchMidpointHz
            if (a.hz > line) == (b.hz > line) {
                stroke(context, start, end, theme.pitch(a.hz))
            } else {
                let fraction = (line - a.hz) / (b.hz - a.hz)
                let cross = CGPoint(x: start.x + (end.x - start.x) * fraction, y: lineY)
                stroke(context, start, cross, theme.pitch(a.hz))
                stroke(context, cross, end, theme.pitch(b.hz))
            }
        }
    }

    private func stroke(_ context: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}
