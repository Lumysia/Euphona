import Foundation

/// A smoothed F0 trace for drawing a recording.
public struct PitchTrace: Sendable {
    public static let stepSeconds = 0.004
    public static let maximumGapSeconds = 0.35
    public static let maximumHz = 600.0

    public struct Point: Sendable, Equatable {
        public var time: Double
        public var hz: Double
        /// Points with different runs are not joined.
        public var run: Int
    }

    public let points: [Point]

    /// Window centers inside a speech segment, joined by uniform Catmull-Rom splines. A new run starts
    /// at each segment change or gap longer than 0.35 s.
    public init(result: EuphonaResult) {
        let segments = result.speech.segments
        let samples: [(time: Double, hz: Double, segment: Int)] = result.f0.windows.compactMap { window in
            guard let hz = window.f0Hz else { return nil }
            let time = (window.startSeconds + window.endSeconds) / 2
            let segment = segments.isEmpty ? 0 : segments.firstIndex { time >= $0.startSeconds && time < $0.endSeconds } ?? -1
            return segment >= 0 ? (time, hz, segment) : nil
        }.sorted { $0.time < $1.time }

        var runs: [[(time: Double, hz: Double)]] = []
        var lastSegment: Int?
        for sample in samples {
            if let last = runs.last?.last, lastSegment == sample.segment, sample.time - last.time <= Self.maximumGapSeconds {
                runs[runs.count - 1].append((sample.time, sample.hz))
            } else {
                runs.append([(sample.time, sample.hz)])
            }
            lastSegment = sample.segment
        }

        var output: [Point] = []
        for (run, values) in runs.enumerated() {
            output.append(Point(time: values[0].time, hz: values[0].hz, run: run))
            guard values.count > 1 else { continue }
            for index in 0..<(values.count - 1) {
                let p0 = values[max(0, index - 1)].hz
                let p1 = values[index]
                let p2 = values[index + 1]
                let p3 = values[min(values.count - 1, index + 2)].hz
                let steps = max(1, Int(((p2.time - p1.time) / Self.stepSeconds).rounded(.up)))
                for step in 1...steps {
                    let t = Double(step) / Double(steps)
                    let hz = 0.5 * (2 * p1.hz + (-p0 + p2.hz) * t + (2 * p0 - 5 * p1.hz + 4 * p2.hz - p3) * t * t
                        + (-p0 + 3 * p1.hz - 3 * p2.hz + p3) * t * t * t)
                    output.append(Point(time: p1.time + (p2.time - p1.time) * t, hz: min(max(hz, 0), Self.maximumHz), run: run))
                }
            }
        }
        points = output
    }

    /// The nearest point within 0.2 s.
    public func hz(at time: Double) -> Double? {
        guard !points.isEmpty else { return nil }
        var low = 0, high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].time < time { low = mid + 1 } else { high = mid }
        }
        let candidates = [points[low], points[max(low - 1, 0)]]
        guard let nearest = candidates.min(by: { abs($0.time - time) < abs($1.time - time) }),
              abs(nearest.time - time) <= 0.2 else { return nil }
        return nearest.hz
    }

    /// Chart ceiling: the peak rounded up to 50 Hz, kept within 300–600 Hz.
    public var displayMaximumHz: Double {
        let peak = points.map(\.hz).max() ?? 300
        return min(max((peak / 50).rounded(.up) * 50, 300), Self.maximumHz)
    }
}
