import EuphonaKit
import SwiftUI

/// The last 3 s of pitch over pink and blue bands split at 165 Hz, with the target band or glide.
struct PitchChart: View {
    @Environment(\.theme) private var theme
    var monitor: PitchMonitor
    var low: Double
    var high: Double
    var style: PitchChartStyle
    var gapSeconds: Double
    var target: PitchTarget?

    var body: some View {
        TimelineView(.animation(paused: monitor.state != .running && monitor.replay.playhead == nil)) { _ in
            Canvas { context, size in draw(context, size) }
        }
        .background(bands)
        .accessibilityHidden(true)
    }

    private func y(_ hz: Double, _ height: CGFloat) -> CGFloat {
        height * (1 - CGFloat((min(max(hz, low), high) - low) / (high - low)))
    }

    private var bands: some View {
        GeometryReader { proxy in
            let line = y(Scoring.pitchMidpointHz, proxy.size.height)
            VStack(spacing: 0) {
                LinearGradient(colors: [theme.feminineFill.opacity(0.22), theme.feminineFill.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                    .frame(height: line)
                LinearGradient(colors: [theme.masculineFill.opacity(0.06), theme.masculineFill.opacity(0.18)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func drawTarget(_ target: PitchTarget, _ context: GraphicsContext, _ size: CGSize, start: Double, x: (Double) -> CGFloat) {
        let steps = 90
        let times = (0...steps).map { start + PitchMonitor.windowSeconds * Double($0) / Double(steps) }
        let ranges = times.map { target.range(at: $0) }
        var top = Path(), bottom = Path()
        top.addLines(zip(times, ranges).map { CGPoint(x: x($0), y: y($1.upperBound, size.height)) })
        bottom.addLines(zip(times, ranges).map { CGPoint(x: x($0), y: y($1.lowerBound, size.height)) })
        var area = top
        area.addLines(zip(times, ranges).reversed().map { CGPoint(x: x($0), y: y($1.lowerBound, size.height)) })
        area.closeSubpath()
        context.fill(area, with: .style(.tint.opacity(0.22)))
        for edge in [top, bottom] {
            context.stroke(edge, with: .style(.tint.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        let end = monitor.windowEnd
        let start = end - PitchMonitor.windowSeconds
        func x(_ time: Double) -> CGFloat { CGFloat((time - start) / PitchMonitor.windowSeconds) * size.width }

        if let target { drawTarget(target, context, size, start: start, x: x) }

        for tick in PitchChartMath.ticks(min: low, max: high) {
            let isLine = tick == Scoring.pitchMidpointHz
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y(tick, size.height)))
            path.addLine(to: CGPoint(x: size.width, y: y(tick, size.height)))
            context.stroke(path, with: .color(.primary.opacity(isLine ? 0.35 : 0.08)), lineWidth: isLine ? 1.5 : 1)
            context.draw(Text(verbatim: "\(Int(tick))").font(.caption2.weight(isLine ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isLine ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)),
                         at: CGPoint(x: 10, y: y(tick, size.height) - 2), anchor: .bottomLeading)
        }

        let visible = monitor.points.filter { $0.time >= start - PitchMonitor.windowSeconds && $0.time <= end }
        var runs: [[CGPoint]] = []
        var previous: Double?
        for point in visible {
            guard let hz = point.hz else { continue }
            if let previous, point.time - previous <= gapSeconds { runs[runs.count - 1].append(CGPoint(x: x(point.time), y: y(hz, size.height))) }
            else { runs.append([CGPoint(x: x(point.time), y: y(hz, size.height))]) }
            previous = point.time
        }

        let trace = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: theme.deepPink, location: 0), .init(color: theme.deepPink, location: max(0, y(Scoring.pitchMidpointHz, size.height) / size.height - 0.001)),
                             .init(color: theme.deepBlue, location: min(1, y(Scoring.pitchMidpointHz, size.height) / size.height + 0.001)), .init(color: theme.deepBlue, location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        for run in runs {
            if style == .dots || run.count == 1 {
                for point in run {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: trace)
                }
            } else {
                var path = Path()
                path.move(to: run[0])
                for segment in PitchChartMath.bSpline(run) {
                    path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
                }
                var glow = context
                glow.addFilter(.blur(radius: 6))
                glow.stroke(path, with: trace, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: trace, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }

        if monitor.replay.playhead == nil {
            let voiced = visible.filter { $0.time >= start }.compactMap(\.hz)
            if !voiced.isEmpty {
                let average = voiced.reduce(0, +) / Double(voiced.count)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y(average, size.height)))
                path.addLine(to: CGPoint(x: size.width, y: y(average, size.height)))
                context.stroke(path, with: .color(.primary.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                context.draw(Text(.pitchAverageF0Format(Float(average))).font(.caption.weight(.semibold)).foregroundStyle(.secondary),
                             at: CGPoint(x: size.width - 10, y: y(average, size.height) - 4), anchor: .bottomTrailing)
            }
        } else if let playhead = monitor.replay.playhead {
            var path = Path()
            path.move(to: CGPoint(x: x(playhead), y: 0))
            path.addLine(to: CGPoint(x: x(playhead), y: size.height))
            context.stroke(path, with: .style(.tint), lineWidth: 3)
        }
    }
}
