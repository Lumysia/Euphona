import Foundation

/// Turns live F0 into the voice orb's pink/blue balance while recording.
///
/// Pitch is mapped on the score's own semitone scale (`Scoring.pitchProgress`): fully blue at typical
/// masculine pitch, fully pink at typical feminine pitch. A short median drops the tracker's
/// isolated octave jumps and exponential smoothing calms vibrato, so the color doesn't flicker. It is
/// held through the short gaps between words, then eased back to the resting balance rather than snapping.
public struct PitchBalance: Sendable {
    /// Semitones from the midpoint to either end.
    public static let span = 6 * log2(Scoring.femininePitchHz / Scoring.masculinePitchHz)
    /// Exponential smoothing per voiced frame (at 30 frames/s, a time constant of about 100 ms).
    public static let smoothing = 0.28
    public static let holdSeconds = 0.8
    public static let relaxSeconds = 1.2
    /// Voiced frames in the median (about 165 ms at 30 frames/s).
    public static let medianFrames = 5

    private var recent: [Double] = []
    private var semitones: Double?
    private var lastVoiced = -Double.infinity

    public init() {}

    /// The balance a pitch maps to: 0 fully masculine (blue), 1 fully feminine (pink).
    public static func balance(hz: Double) -> Double {
        guard hz > 0 else { return 0.5 }
        return Scoring.pitchProgress(hz, goal: .feminization) / 100
    }

    public mutating func ingest(_ frames: [F0Frame]) {
        for frame in frames where frame.voiced && frame.f0Hz > 0 {
            recent.append(12 * log2(Double(frame.f0Hz) / Scoring.pitchMidpointHz))
            if recent.count > Self.medianFrames { recent.removeFirst() }
            let value = recent.sorted()[recent.count / 2]
            semitones = semitones.map { $0 + (value - $0) * Self.smoothing } ?? value
            lastVoiced = max(lastVoiced, frame.timestamp)
        }
    }

    /// The balance to show at `time` (seconds on the frames' clock), falling back to `resting`.
    public func balance(at time: Double, resting: Double) -> Double {
        guard let semitones else { return resting }
        let live = min(max(0.5 + semitones / (2 * Self.span), 0), 1)
        let silent = time - lastVoiced - Self.holdSeconds
        guard silent > 0 else { return live }
        let progress = min(silent / Self.relaxSeconds, 1)
        let eased = progress * progress * (3 - 2 * progress)
        return live + (resting - live) * eased
    }
}
