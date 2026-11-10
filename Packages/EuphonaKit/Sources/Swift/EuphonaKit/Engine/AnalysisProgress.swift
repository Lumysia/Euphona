/// What the engine is doing while it analyzes a clip.
public enum AnalysisStage: Int, Sendable, CaseIterable {
    case detectingSpeech
    case analyzingPitch
    case extractingFeatures
    case scoringTimbre
    case scoringFlow
    case calculatingScores
    case measuringVoice
    case scoringVoiceQuality
    case completed
}

public struct AnalysisProgress: Sendable, Equatable {
    public enum Kind: Sendable {
        case voiceAnalysis, voiceQuality

        /// Rough share of run time per stage; the speaker embeddings dominate an analysis.
        fileprivate var stageWeights: [(stage: AnalysisStage, weight: Double)] {
            switch self {
            case .voiceAnalysis: [
                (.detectingSpeech, 0.06), (.analyzingPitch, 0.03), (.extractingFeatures, 0.86),
                (.scoringTimbre, 0.01), (.scoringFlow, 0.02), (.calculatingScores, 0.01), (.completed, 0.01),
            ]
            case .voiceQuality: [
                (.detectingSpeech, 0.25), (.analyzingPitch, 0.10), (.measuringVoice, 0.60),
                (.scoringVoiceQuality, 0.04), (.completed, 0.01),
            ]
            }
        }
    }

    public let kind: Kind
    public let stage: AnalysisStage
    public let stageFraction: Double

    public init(kind: Kind, stage: AnalysisStage, stageFraction: Double) {
        self.kind = kind
        self.stage = stage
        self.stageFraction = stageFraction
    }

    /// Progress across the whole analysis, weighting each stage by its share of the run time.
    public var overallFraction: Double {
        let weights = kind.stageWeights
        guard let index = weights.firstIndex(where: { $0.stage == stage }) else { return 0 }
        let start = weights[..<index].reduce(0) { $0 + $1.weight }
        let fraction = min(max(stageFraction, 0), 1)
        return min(max(start + weights[index].weight * fraction, 0), 1)
    }
}
