import Foundation

/// How feminine (1) or masculine (0) a voice reads: the timbre model's own reading. The voice orb and
/// the result's feminine and masculine shares show it; the overall score is a separate measure of
/// progress toward the goal.
extension EuphonaResult {
    public var voiceBalance: Double { min(max(timbre.score / 100, 0), 1) }
}

extension AnalysisRecord {
    public var voiceBalance: Double { min(max(timbreScore / 100, 0), 1) }
}
