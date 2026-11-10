import Foundation

/// One voice analysis: the component scores over time, the overall score and how it was reached.
public struct EuphonaResult: Codable, Sendable, Equatable {
    /// The models that produced it (`EuphonaAnalyzer.modelVersion`).
    public var modelVersion: String
    public var scoreProfile: ScoreProfile
    /// Length of the recording.
    public var inputSeconds: Double
    public var speech: Speech
    public var f0: F0Metrics
    /// Timbre: 0 (masculine) to 100 (feminine).
    public var timbre: ScoreTrack
    public var flow: Flow
    /// How little audible strain, 0...100 (100 = none above what healthy speakers show).
    public var ease: Double
    /// Mean harmonics-to-noise ratio over voiced speech.
    public var hnrDb: Double?

    public struct Speech: Codable, Sendable, Equatable {
        public var seconds: Double
        public var segments: [SpeechSegment]
    }

    /// Where speech was found in the recording, and where it sits in the speech-only timeline.
    /// Pace and pauses, and the flow score they give (`SpeechFlow`).
    public struct Flow: Codable, Sendable, Equatable {
        public var score: Double
        /// Syllable peaks per second of speech.
        public var articulationRate: Double
        /// Silent gaps between speech segments, over the span from first to last speech.
        public var pauseShare: Double

        public init(score: Double, articulationRate: Double, pauseShare: Double) {
            self.score = score
            self.articulationRate = articulationRate
            self.pauseShare = pauseShare
        }
    }

    public struct SpeechSegment: Codable, Sendable, Equatable {
        public var startSeconds: Double
        public var endSeconds: Double
        public var speechStartSeconds: Double
        public var speechEndSeconds: Double
    }

    public struct F0Metrics: Codable, Sendable, Equatable {
        public var standardDeviationHz: Double?
        /// Mean pitch in 50 ms windows of the speech-only timeline.
        public var windows: [F0Window]

        public init(standardDeviationHz: Double?, windows: [F0Window]) {
            self.standardDeviationHz = standardDeviationHz
            self.windows = windows
        }

        /// The speaking pitch: the median of the voiced windows, so a laugh, a squeal or music under
        /// the voice moves it only as far as it lasts, never by how high it goes.
        public var speakingHz: Double? { Self.median(windows.compactMap(\.f0Hz)) }

        public static func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted(), middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }
    }

    public struct F0Window: Codable, Sendable, Equatable {
        public var startSeconds: Double
        public var endSeconds: Double
        public var f0Hz: Double?
    }

    /// A score for the whole recording and for each embedding window of the speech-only timeline.
    public struct ScoreTrack: Codable, Sendable, Equatable {
        public var score: Double
        public var windows: [ScoredWindow]
    }

    public struct ScoredWindow: Codable, Sendable, Equatable {
        public var startSeconds: Double
        public var endSeconds: Double
        public var score: Double
    }
}

extension EuphonaResult {
    /// The overall score, computed from the components with today's rules, so old results follow
    /// any change to them.
    public var composite: ScoreBreakdown {
        Scoring.score(profile: scoreProfile, timbre: timbre.score, flow: flow.score, ease: ease, f0Hz: f0.speakingHz)
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: json)
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
