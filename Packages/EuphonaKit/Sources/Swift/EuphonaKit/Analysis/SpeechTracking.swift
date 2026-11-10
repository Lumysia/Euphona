import Foundation

/// Merges VAD intervals from overlapping windows, counting their union once.
public struct SpeechIntervalTracker: Sendable {
    static let mergeEpsilon = 0.001
    private var intervals: [SpeechInterval] = []

    public init() {}

    public var totalSeconds: Double { intervals.reduce(0) { $0 + $1.duration } }

    @discardableResult
    public mutating func add(_ interval: SpeechInterval) -> Double {
        guard interval.start.isFinite, interval.end.isFinite, interval.end > interval.start else { return totalSeconds }
        var merged: [SpeechInterval] = []
        for candidate in (intervals + [interval]).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, candidate.start <= last.end + Self.mergeEpsilon {
                merged[merged.count - 1].end = max(last.end, candidate.end)
            } else {
                merged.append(candidate)
            }
        }
        intervals = merged
        return totalSeconds
    }
}

/// Counts speech while recording: every 300 ms, VAD runs over the last 0.9 s of audio and the
/// intervals found are merged on the recording's timeline.
public struct LiveSpeechCounter: Sendable {
    public static let sampleRate = 16_000
    public static let stepSamples = sampleRate * 300 / 1000
    public static let windowSamples = Int(Double(sampleRate) * 0.9)

    /// The audio VAD should look at next, and where it starts on the recording's timeline.
    public struct Window: Sendable {
        public var samples: [Float]
        public var startSample: Int
    }

    private var rolling: [Float] = []
    private var capturedSamples = 0
    private var samplesSinceWindow = 0
    private var tracker = SpeechIntervalTracker()
    private let normalizesLevel: Bool
    private var level = SpeechLevel()

    /// `normalizesLevel` scales VAD windows with `SpeechLevel`, for unprocessed (measurement) input.
    public init(normalizesLevel: Bool = false) {
        self.normalizesLevel = normalizesLevel
    }

    /// The gain the recording so far should be played to analysis with.
    public var levelGain: Float { normalizesLevel ? level.gain : 1 }

    public var speechSeconds: Double { tracker.totalSeconds }
    public var recordedSeconds: Double { Double(capturedSamples) / Double(Self.sampleRate) }

    /// Appends 16 kHz mono samples and returns the VAD windows that became due.
    public mutating func append(_ samples: [Float]) -> [Window] {
        var due: [Window] = []
        for sample in samples {
            rolling.append(sample)
            capturedSamples += 1
            samplesSinceWindow += 1
            if samplesSinceWindow >= Self.stepSamples {
                if rolling.count > Self.windowSamples { rolling.removeFirst(rolling.count - Self.windowSamples) }
                if normalizesLevel { level.observe(rolling) }
                due.append(currentWindow())
                samplesSinceWindow = 0
            }
        }
        if rolling.count > Self.windowSamples { rolling.removeFirst(rolling.count - Self.windowSamples) }
        return due
    }

    /// The final window when recording stops, so the tail is counted too.
    public mutating func finalWindow() -> Window? {
        guard !rolling.isEmpty else { return nil }
        if normalizesLevel { level.observe(rolling) }
        return currentWindow()
    }

    /// Adds VAD intervals found in `window` (relative to the window start).
    public mutating func record(_ segments: [SpeechInterval], in window: Window) {
        let start = Double(window.startSample) / Double(Self.sampleRate)
        for segment in segments {
            tracker.add(SpeechInterval(start: start + segment.start, end: start + segment.end))
        }
    }

    private func currentWindow() -> Window {
        Window(samples: SpeechLevel.apply(levelGain, to: rolling), startSample: capturedSamples - rolling.count)
    }
}
