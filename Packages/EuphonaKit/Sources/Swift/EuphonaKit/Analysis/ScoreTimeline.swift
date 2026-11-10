import Foundation

/// Peak amplitude per bucket, for drawing a recording.
public enum Waveform {
    public static let bucketCount = 2048

    public static func peaks(of audio: PCMBuffer, buckets requested: Int = bucketCount) -> [Float] {
        let channels = max(audio.channels, 1)
        let frames = audio.samples.count / channels
        guard frames > 0, requested > 0 else { return [] }
        let buckets = min(requested, frames)
        return (0..<buckets).map { bucket in
            let start = bucket * frames / buckets
            let end = max(start + 1, (bucket + 1) * frames / buckets)
            var peak: Float = 0
            for index in (start * channels)..<(end * channels) { peak = max(peak, abs(audio.samples[index])) }
            return min(peak, 1)
        }
    }
}

/// The composite score of one VAD speech segment.
public struct SegmentScore: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var score: Double

    /// Averages timbre over the segment, weighted by overlap, takes its speaking pitch the way the whole
    /// recording's is taken (`F0Metrics.speakingHz`), and scores it with the recording's flow and ease
    /// (both judge the whole recording).
    public static func segments(of result: EuphonaResult) -> [SegmentScore] {
        result.speech.segments.map { segment in
            let range = segment.startSeconds..<segment.endSeconds
            let standard = weightedAverage(result.timbre.windows.map { ($0.startSeconds, $0.endSeconds, $0.score) }, over: range)
                ?? result.timbre.score
            let f0 = EuphonaResult.F0Metrics.median(result.f0.windows.filter {
                min($0.endSeconds, range.upperBound) > max($0.startSeconds, range.lowerBound)
            }.compactMap(\.f0Hz))
            let score = EuphonaAnalyzer.score(
                profile: result.scoreProfile, timbreScore: standard, flow: result.flow.score, ease: result.ease, f0Hz: f0
            )
            return SegmentScore(start: segment.startSeconds, end: segment.endSeconds, score: score.finalScore)
        }
    }

    private static func weightedAverage(_ windows: [(Double, Double, Double?)], over range: Range<Double>) -> Double? {
        var sum = 0.0
        var weight = 0.0
        for (start, end, value) in windows {
            let overlap = min(end, range.upperBound) - max(start, range.lowerBound)
            guard overlap > 0, let value else { continue }
            sum += value * overlap
            weight += overlap
        }
        return weight > 0 ? sum / weight : nil
    }
}

/// Local composite score over the recording, in fixed bins: local timbre and pitch with the
/// recording's flow and ease. Bins without timbre coverage or outside speech have no point.
public struct ScoreTimeline: Sendable {
    public static let defaultBinCount = 2048

    public struct Point: Sendable, Equatable {
        public var score: Double
        public var timbreScore: Double
        public var f0Hz: Double?
    }

    public let points: [Point?]
    public let duration: Double

    public init(result: EuphonaResult, duration: Double, binCount: Int = defaultBinCount) {
        precondition(duration > 0 && binCount > 0)
        self.duration = duration
        var timbre = WeightedBins(count: binCount, duration: duration)
        result.timbre.windows.forEach { timbre.add($0.startSeconds, $0.endSeconds, $0.score) }
        var f0 = WeightedBins(count: binCount, duration: duration)
        result.f0.windows.forEach { window in window.f0Hz.map { f0.add(window.startSeconds, window.endSeconds, $0) } }

        let segments = result.speech.segments
        points = (0..<binCount).map { index in
            let center = (Double(index) + 0.5) * duration / Double(binCount)
            guard let timbreScore = timbre.average(index),
                  segments.contains(where: { center >= $0.startSeconds && center < $0.endSeconds })
            else { return nil }
            let pitch = f0.average(index)
            let score = EuphonaAnalyzer.score(
                profile: result.scoreProfile, timbreScore: timbreScore, flow: result.flow.score, ease: result.ease, f0Hz: pitch
            )
            return Point(score: score.finalScore, timbreScore: timbreScore, f0Hz: pitch)
        }
    }

    public func point(at seconds: Double) -> Point? {
        guard (0...duration).contains(seconds), !points.isEmpty else { return nil }
        let index = min(max(Int(seconds / duration * Double(points.count)), 0), points.count - 1)
        return points[index]
    }
}

private struct WeightedBins {
    let count: Int
    let duration: Double
    var sums: [Double]
    var weights: [Double]

    init(count: Int, duration: Double) {
        self.count = count
        self.duration = duration
        sums = Array(repeating: 0, count: count)
        weights = Array(repeating: 0, count: count)
    }

    mutating func add(_ start: Double, _ end: Double, _ value: Double) {
        guard end > start, !value.isNaN else { return }
        let first = min(max(Int((start / duration * Double(count)).rounded(.down)), 0), count - 1)
        let last = min(max(Int((end / duration * Double(count)).rounded(.up)), first + 1), count)
        let binDuration = duration / Double(count)
        for bin in first..<last {
            let binStart = Double(bin) * binDuration
            let overlap = min(end, binStart + binDuration) - max(start, binStart)
            guard overlap > 0 else { continue }
            sums[bin] += value * overlap
            weights[bin] += overlap
        }
    }

    func average(_ index: Int) -> Double? { weights[index] > 0 ? sums[index] / weights[index] : nil }
}
