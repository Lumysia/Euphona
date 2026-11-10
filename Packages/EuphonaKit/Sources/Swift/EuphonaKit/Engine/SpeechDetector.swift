import Foundation

/// Speech segments from Silero VAD, following Silero's own `get_speech_timestamps` algorithm.
struct SpeechDetector: Sendable {
    static let sampleRate = 16_000
    private static let window = 512
    private static let context = 64

    var startThreshold: Float = 0.5
    var minimumSpeechSeconds = 0.25
    var minimumSilenceSeconds = 0.1
    var paddingSeconds = 0.03

    let model: ONNXModel

    /// Sample ranges of speech in 16 kHz mono audio.
    func segments(_ samples: [Float]) throws -> [Range<Int>] {
        let probabilities = try speechProbabilities(samples)
        let endThreshold = max(startThreshold - 0.15, 0.01)
        let minimumSpeech = Int(minimumSpeechSeconds * Double(Self.sampleRate))
        let minimumSilence = Int(minimumSilenceSeconds * Double(Self.sampleRate))
        var speeches: [Range<Int>] = []
        var triggered = false
        var start = 0
        var tentativeEnd = 0
        for (index, probability) in probabilities.enumerated() {
            let position = index * Self.window
            if probability >= startThreshold, tentativeEnd != 0 { tentativeEnd = 0 }
            if probability >= startThreshold, !triggered {
                triggered = true
                start = position
                continue
            }
            if probability < endThreshold, triggered {
                if tentativeEnd == 0 { tentativeEnd = position }
                if position - tentativeEnd < minimumSilence { continue }
                if tentativeEnd - start > minimumSpeech { speeches.append(start..<tentativeEnd) }
                triggered = false
                tentativeEnd = 0
            }
        }
        if triggered, samples.count - start > minimumSpeech { speeches.append(start..<samples.count) }
        return padded(speeches, count: samples.count)
    }

    /// Widens each segment by the padding, splitting short gaps between neighbours.
    private func padded(_ speeches: [Range<Int>], count: Int) -> [Range<Int>] {
        let pad = Int(paddingSeconds * Double(Self.sampleRate))
        var bounds = speeches.map { [$0.lowerBound, $0.upperBound] }
        for i in bounds.indices {
            if i == 0 { bounds[i][0] = max(0, bounds[i][0] - pad) }
            if i + 1 < bounds.count {
                let gap = bounds[i + 1][0] - bounds[i][1]
                if gap < 2 * pad {
                    bounds[i][1] += gap / 2
                    bounds[i + 1][0] = max(0, bounds[i + 1][0] - gap / 2)
                } else {
                    bounds[i][1] = min(count, bounds[i][1] + pad)
                    bounds[i + 1][0] = max(0, bounds[i + 1][0] - pad)
                }
            } else {
                bounds[i][1] = min(count, bounds[i][1] + pad)
            }
        }
        return bounds.filter { $0[1] > $0[0] }.map { $0[0]..<$0[1] }
    }

    private func speechProbabilities(_ samples: [Float]) throws -> [Float] {
        var state = Tensor([Float](repeating: 0, count: 2 * 128), shape: [2, 1, 128])
        var context = [Float](repeating: 0, count: Self.context)
        var probabilities: [Float] = []
        probabilities.reserveCapacity(samples.count / Self.window + 1)
        var start = 0
        while start < samples.count {
            var chunk = context
            let end = min(start + Self.window, samples.count)
            chunk += samples[start..<end]
            if end - start < Self.window { chunk += [Float](repeating: 0, count: Self.window - (end - start)) }
            let out = try model.run(
                [("input", .floats(Tensor(chunk, shape: [1, chunk.count]))), ("state", .floats(state)),
                 ("sr", .int64(value: Int64(Self.sampleRate)))],
                outputs: ["output", "stateN"])
            probabilities.append(out[0].values[0])
            state = out[1]
            context = Array(chunk.suffix(Self.context))
            start += Self.window
        }
        return probabilities
    }
}
