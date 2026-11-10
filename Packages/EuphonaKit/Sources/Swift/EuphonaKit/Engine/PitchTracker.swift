import Foundation

/// SwiftF0 pitch per 16 ms frame, with its confidence.
struct PitchTrack: Sendable {
    static let hop = 256
    /// The centre of frame 0 in the input (SwiftF0's STFT padding).
    static let centreOffset = 127.5

    var hz: [Float]
    var confidence: [Float]

    static func time(ofFrame index: Int) -> Double {
        (Double(index * hop) + centreOffset) / Double(SpeechDetector.sampleRate)
    }

    /// Pitch where the frame counts as voiced, nil elsewhere.
    func voiced(minHz: Float, maxHz: Float, minConfidence: Float) -> [Float?] {
        zip(hz, confidence).map { f, c in c >= minConfidence && f >= minHz && f <= maxHz ? f : nil }
    }
}

struct PitchTracker: Sendable {
    let model: ONNXModel

    func track(_ samples: [Float]) throws -> PitchTrack {
        var input = samples
        if input.count < PitchTrack.hop { input += [Float](repeating: 0, count: PitchTrack.hop - input.count) }
        let out = try model.run([("input_audio", .floats(Tensor(input, shape: [1, input.count])))],
                                outputs: ["pitch_hz", "confidence"])
        return PitchTrack(hz: out[0].values, confidence: out[1].values)
    }
}
