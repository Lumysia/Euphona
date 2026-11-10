import Foundation
import Synchronization

public struct TimbreFrame: Sendable, Equatable {
    /// End of the window the score describes, on the stream's timeline.
    public var timestamp: Double
    /// 0 (masculine) to 100 (feminine), as in a full analysis.
    public var score: Double
}

/// Live timbre: the timbre model on the last 1.5 s of audio, every half second. A window is scored
/// only when at least half of it is speech, and then only its speech, the way a full analysis
/// embeds speech segments.
public final class RealtimeTimbreStream: Sendable {
    public static let sampleRate = SpeechDetector.sampleRate
    static let windowSamples = EmbeddingWindows.length
    static let hopSamples = sampleRate / 2
    static let minimumSpeechSamples = windowSamples / 2

    private struct State {
        var buffer: [Float] = []
        var sinceLastRun = 0
        var received = 0
    }

    private let speech: SpeechDetector
    private let encoder: SpeakerEncoder
    private let heads: ScoreHeads
    private let state = Mutex(State())

    public init(analyzer: EuphonaAnalyzer) {
        speech = analyzer.speech
        encoder = analyzer.encoder
        heads = analyzer.heads
    }

    /// Feeds 16 kHz mono samples; returns a frame when a window was due and held enough speech.
    public func process(_ samples: [Float]) throws -> TimbreFrame? {
        let window: (samples: [Float], end: Int)? = state.withLock { s in
            s.buffer += samples
            s.received += samples.count
            s.sinceLastRun += samples.count
            if s.buffer.count > Self.windowSamples { s.buffer.removeFirst(s.buffer.count - Self.windowSamples) }
            guard s.sinceLastRun >= Self.hopSamples, s.buffer.count == Self.windowSamples else { return nil }
            s.sinceLastRun = 0
            return (s.buffer, s.received)
        }
        guard let window else { return nil }
        let voiced = try speech.segments(window.samples).flatMap { window.samples[$0] }
        guard voiced.count >= Self.minimumSpeechSamples else { return nil }
        let embedding = try encoder.embed(voiced, EmbeddingWindows(segments: [0..<voiced.count]))
        guard let probability = try heads.timbre(embedding).first else { return nil }
        return TimbreFrame(timestamp: Double(window.end) / Double(Self.sampleRate), score: Double(probability) * 100)
    }

    public func reset() {
        state.withLock { $0 = State() }
    }
}
