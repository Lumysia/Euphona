import Foundation

/// The components of the overall score: timbre and pitch make the voice part; flow and ease the
/// fluency, which follows the lower of the two.
public enum ScoreMetric: Sendable, CaseIterable {
    case timbre, f0, flow, ease
}
