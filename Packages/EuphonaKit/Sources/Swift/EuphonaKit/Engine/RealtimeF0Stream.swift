import Foundation
import Synchronization

public struct F0Frame: Sendable, Equatable {
    public var timestamp: Double
    public var f0Hz: Float
    public var confidence: Float
    public var voiced: Bool

    public init(timestamp: Double, f0Hz: Float, confidence: Float, voiced: Bool) {
        self.timestamp = timestamp
        self.f0Hz = f0Hz
        self.confidence = confidence
        self.voiced = voiced
    }
}

/// Live pitch: SwiftF0 over a sliding context, emitting each new frame once.
public final class RealtimeF0Stream: Sendable {
    public static let sampleRate = 16_000
    /// 160 ms of context, enough history for the frames emitted between runs.
    public static let contextSamples = 2560

    /// Run spacing for an output rate: 16000 / rate, kept within 256...1024 samples.
    public static func hopSamples(forOutputRate rate: Int) -> Int { min(max(sampleRate / max(rate, 1), 256), 1024) }

    private struct State {
        var buffer: [Float] = []
        var sinceLastRun = 0
        var emittedUntil: Double
        /// When the next frame is due at the requested output rate.
        var nextDue: Double
        /// Samples dropped from the front of the buffer so far.
        var consumed = 0
    }

    private let tracker: PitchTracker
    private let settings: AnalyzerSettings
    private let hop: Int
    /// Time between emitted frames at the requested rate; 0 emits every SwiftF0 frame.
    private let spacing: Double
    private let state: Mutex<State>
    private let start: Double

    /// `outputRateHz` <= 0 emits every SwiftF0 frame (62.5 per second).
    public init(analyzer: EuphonaAnalyzer, outputRateHz: Double, startTimestamp: Double = 0) {
        tracker = analyzer.pitch
        settings = analyzer.settings
        hop = outputRateHz > 0 ? Self.hopSamples(forOutputRate: Int(outputRateHz)) : PitchTrack.hop
        spacing = outputRateHz > 0 ? 1 / outputRateHz : 0
        start = startTimestamp
        state = Mutex(State(emittedUntil: startTimestamp - 1, nextDue: startTimestamp))
    }

    /// Feeds 16 kHz mono samples and returns the frames they completed.
    public func process(_ samples: [Float]) throws -> [F0Frame] {
        try state.withLock { s in
            s.buffer += samples
            s.sinceLastRun += samples.count
            let overflow = s.buffer.count - Self.contextSamples
            if overflow > 0 {
                s.buffer.removeFirst(overflow)
                s.consumed += overflow
            }
            guard s.sinceLastRun >= hop, s.buffer.count >= PitchTrack.hop * 4 else { return [] }
            s.sinceLastRun = 0
            let track = try tracker.track(s.buffer)
            let offset = Double(s.consumed) / Double(SpeechDetector.sampleRate)
            var frames: [F0Frame] = []
            // The newest frames lack right-hand context; hold back the last two until the next run.
            for index in 0..<max(0, track.hz.count - 2) {
                let time = start + offset + PitchTrack.time(ofFrame: index)
                // On SwiftF0's 16 ms grid, take the frame nearest each due time.
                let halfFrame = Double(PitchTrack.hop) / Double(SpeechDetector.sampleRate) / 2
                guard time > s.emittedUntil + 1e-6, time + halfFrame >= s.nextDue else { continue }
                while s.nextDue <= time + halfFrame { s.nextDue += max(spacing, 1e-9) }
                let f = track.hz[index], c = track.confidence[index]
                let voiced = c >= settings.minConfidence && f >= settings.minF0Hz && f <= settings.maxF0Hz
                frames.append(F0Frame(timestamp: time, f0Hz: f, confidence: c, voiced: voiced))
                s.emittedUntil = time
            }
            return frames
        }
    }

    public func reset() {
        state.withLock { s in s = State(emittedUntil: start - 1, nextDue: start) }
    }
}
