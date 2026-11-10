import CoreGraphics

/// Axis and curve rules of the live pitch chart.
public enum PitchChartMath {
    /// Ticks every 20/50/100/200 Hz depending on the span, plus the pitch midpoint when no tick is within
/// 0.5 Hz of it.
    public static func ticks(min low: Double, max high: Double) -> [Double] {
        let span = Swift.max(high - low, 1)
        let step: Double = span <= 120 ? 20 : span <= 250 ? 50 : span <= 600 ? 100 : 200
        var ticks = Array(stride(from: (low / step).rounded(.up) * step, through: high, by: step))
        let line = Scoring.pitchMidpointHz.rounded()
        if (low...high).contains(line), !ticks.contains(where: { abs($0 - line) < 0.5 }) {
            ticks.append(line)
            ticks.sort()
        }
        return ticks
    }

    /// A uniform cubic B-spline through `points` as Bézier segments, with mirrored phantom ends and
    /// handle x clamped to each segment so time never runs backwards. Fewer than four control points
    /// (after padding) gives the polyline.
    public static func bSpline(_ points: [CGPoint]) -> [(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)] {
        guard points.count >= 2 else { return [] }
        let padded = [CGPoint(x: 2 * points[0].x - points[1].x, y: 2 * points[0].y - points[1].y)] + points
            + [CGPoint(x: 2 * points[points.count - 1].x - points[points.count - 2].x,
                       y: 2 * points[points.count - 1].y - points[points.count - 2].y)]
        guard padded.count >= 4 else {
            return zip(points, points.dropFirst()).map { ($0, $0, $1, $1) }
        }
        func knot(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + 4 * b.x + c.x) / 6, y: (a.y + 4 * b.y + c.y) / 6)
        }
        return (0..<(padded.count - 3)).map { index in
            let p0 = padded[index], p1 = padded[index + 1], p2 = padded[index + 2], p3 = padded[index + 3]
            let start = knot(p0, p1, p2)
            let end = knot(p1, p2, p3)
            func clampX(_ point: CGPoint) -> CGPoint {
                CGPoint(x: Swift.min(Swift.max(point.x, Swift.min(start.x, end.x)), Swift.max(start.x, end.x)), y: point.y)
            }
            let control1 = clampX(CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6))
            let control2 = clampX(CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
            return (start, control1, control2, end)
        }
    }
}
