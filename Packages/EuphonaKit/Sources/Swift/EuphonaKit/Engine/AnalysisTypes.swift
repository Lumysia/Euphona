import Foundation

/// Which voice direction the overall score rewards.
public enum ScoreProfile: String, Codable, Sendable, CaseIterable {
    case feminization
    case masculinization
}

/// Pitch and threading settings, read when an analyzer is created.
public struct AnalyzerSettings: Sendable, Equatable, Codable {
    public var threads: Int
    public var minF0Hz: Float
    public var maxF0Hz: Float
    public var minConfidence: Float

    public init(threads: Int, minF0Hz: Float, maxF0Hz: Float, minConfidence: Float) {
        self.threads = threads
        self.minF0Hz = minF0Hz
        self.maxF0Hz = maxF0Hz
        self.minConfidence = minConfidence
    }

    /// Three quarters of the cores, 75–350 Hz, confidence 0.9.
    public static let standard = AnalyzerSettings(
        threads: defaultThreads, minF0Hz: 75, maxF0Hz: 350, minConfidence: 0.9
    )

    public static var defaultThreads: Int { max(1, ProcessInfo.processInfo.activeProcessorCount * 3 / 4) }
    public static var maximumThreads: Int { min(ProcessInfo.processInfo.activeProcessorCount, 8) }
    public static let f0Range: ClosedRange<Float> = 50...1000
    public static let minimumF0Span: Float = 20
    public static let confidenceRange: ClosedRange<Float> = 0.3...0.99
}

/// Mono or interleaved float PCM in [-1, 1].
public struct PCMBuffer: Sendable {
    public var samples: [Float]
    public var sampleRate: Int
    public var channels: Int

    public init(samples: [Float], sampleRate: Int, channels: Int = 1) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var duration: TimeInterval {
        sampleRate > 0 && channels > 0 ? Double(samples.count / channels) / Double(sampleRate) : 0
    }
}

public struct SpeechInterval: Sendable, Equatable, Codable {
    public var start: TimeInterval
    public var end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end - start) }
}

/// A failure of the analysis engine.
public struct AnalysisError: Error, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case model, noSpeech, unsupportedFormat, internalError
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    static let noSpeech = AnalysisError(kind: .noSpeech, message: "no speech found")
}
