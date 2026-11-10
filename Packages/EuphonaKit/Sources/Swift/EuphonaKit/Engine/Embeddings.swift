import Accelerate
import Foundation

/// Where the speaker embeddings are taken: 1.515 s windows every 0.1 s inside each speech segment;
/// a segment shorter than one window is used whole.
struct EmbeddingWindows: Sendable {
    static let length = 24_240
    static let stride = 1_600
    static let dimensions = 192

    var ranges: [Range<Int>]

    init(segments: [Range<Int>]) {
        var ranges: [Range<Int>] = []
        for segment in segments {
            if segment.count <= Self.length {
                ranges.append(segment)
                continue
            }
            let last = segment.upperBound - Self.length
            var start = segment.lowerBound
            while start <= last {
                ranges.append(start..<start + Self.length)
                start += Self.stride
            }
            if ranges.last?.lowerBound != last { ranges.append(last..<last + Self.length) }
        }
        self.ranges = ranges
    }
}

/// SpeechBrain ECAPA-TDNN (Apache 2.0), exported with its filterbank front end.
struct SpeakerEncoder: Sendable {
    static let batch = 16
    let model: ONNXModel

    func embed(_ samples: [Float], _ windows: EmbeddingWindows,
               progress: (Int, Int) -> Void = { _, _ in }) throws -> [[Float]] {
        var embeddings = [[Float]](repeating: [], count: windows.ranges.count)
        let byLength = Dictionary(grouping: windows.ranges.indices, by: { windows.ranges[$0].count })
        var done = 0
        for (length, indices) in byLength.sorted(by: { $0.key > $1.key }) {
            for chunk in stride(from: 0, to: indices.count, by: Self.batch).map({ Array(indices[$0..<min($0 + Self.batch, indices.count)]) }) {
                var input: [Float] = []
                input.reserveCapacity(chunk.count * length)
                for index in chunk { input += samples[windows.ranges[index]] }
                let out = try model.run([("waveforms", .floats(Tensor(input, shape: [chunk.count, length])))],
                                        outputs: ["embeddings"])[0]
                for (row, index) in chunk.enumerated() {
                    embeddings[index] = Array(out.values[row * EmbeddingWindows.dimensions..<(row + 1) * EmbeddingWindows.dimensions])
                }
                done += chunk.count
                progress(done, windows.ranges.count)
            }
        }
        return embeddings
    }
}

enum EmbeddingMath {
    static func normalized(_ v: [Float]) -> [Float] {
        let norm = max(sqrt(vDSP.sumOfSquares(v)), 1e-12)
        return vDSP.divide(v, norm)
    }

    /// A recording's embedding statistics: the normalized mean of the normalized windows, then their
    /// per-dimension standard deviation.
    static func statistics(_ embeddings: [[Float]]) -> (mean: [Float], std: [Float]) {
        let units = embeddings.map(Self.normalized)
        let n = Float(units.count)
        var mean = [Float](repeating: 0, count: EmbeddingWindows.dimensions)
        for e in units { vDSP.add(mean, e, result: &mean) }
        mean = vDSP.divide(mean, n)
        var variance = [Float](repeating: 0, count: EmbeddingWindows.dimensions)
        for e in units {
            let d = vDSP.subtract(e, mean)
            vDSP.add(variance, vDSP.multiply(d, d), result: &variance)
        }
        return (normalized(mean), vDSP.divide(variance, n).map { $0.squareRoot() })
    }
}

/// Our timbre head and ease model (see tools/voice-model).
struct ScoreHeads: Sendable {
    let timbre: ONNXModel
    let ease: ONNXModel

    /// Timbre probability per window, 0 (masculine) to 1 (feminine).
    func timbre(_ embeddings: [[Float]]) throws -> [Float] {
        var out: [Float] = []
        for start in stride(from: 0, to: embeddings.count, by: 64) {
            let chunk = embeddings[start..<min(start + 64, embeddings.count)]
            let input = Tensor(chunk.flatMap { $0 }, shape: [chunk.count, EmbeddingWindows.dimensions])
            out += try timbre.run([("embeddings", .floats(input))], outputs: ["probabilities"])[0].values
        }
        return out
    }

    /// Ease 0–100 from a recording's embedding statistics (`EmbeddingMath.statistics`, mean then std).
    func ease(_ statistics: [Float]) throws -> Float {
        let input = Tensor(statistics, shape: [1, statistics.count])
        return try ease.run([("features", .floats(input))], outputs: ["ease"])[0].values[0]
    }
}
