import Foundation
import SwiftData

// CloudKit mirrors these models, so every attribute has a default, nothing is unique, and large blobs
// use external storage (synced as assets).

/// One voice analysis, with its audio and full result.
@Model
public final class AnalysisRecord {
    public var date: Date = Date.now
    public var finalScore: Double = 0
    public var timbreScore: Double = 0
    public var flowScore: Double = 0
    public var easeScore: Double = 0
    public var speakingF0Hz: Double?
    public var f0VariationHz: Double?
    public var inputSeconds: Double = 0
    public var pinned: Bool = false
    public var scoreProfileRaw: String = ScoreProfile.feminization.rawValue
    @Attribute(.externalStorage) public var resultJSON: Data?
    @Attribute(.externalStorage) public var audio: Data?
    /// File extension of `audio`, e.g. "m4a".
    public var audioFormat: String?

    public init(result: EuphonaResult, date: Date = .now, audio: Data?, audioFormat: String?) {
        self.date = date
        self.audio = audio
        self.audioFormat = audioFormat
        refresh(from: result)
    }

    /// Stores `result` and every value derived from it. Returns whether any of them changed.
    @discardableResult
    public func refresh(from result: EuphonaResult) -> Bool {
        let before = (finalScore, timbreScore, flowScore, easeScore, speakingF0Hz, f0VariationHz)
        finalScore = result.composite.finalScore
        timbreScore = result.timbre.score
        flowScore = result.flow.score
        easeScore = result.ease
        speakingF0Hz = result.f0.speakingHz
        f0VariationHz = result.f0.standardDeviationHz
        inputSeconds = result.inputSeconds
        scoreProfileRaw = result.scoreProfile.rawValue
        if self.result != result { resultJSON = try? result.encodedJSON() }
        return before != (finalScore, timbreScore, flowScore, easeScore, speakingF0Hz, f0VariationHz)
    }

    public var scoreProfile: ScoreProfile { ScoreProfile(rawValue: scoreProfileRaw) ?? .feminization }

    public var result: EuphonaResult? { resultJSON.flatMap { try? EuphonaResult(json: $0) } }
}

/// The mean pitch of one realtime pitch session.
@Model
public final class PitchSession {
    public var date: Date = Date.now
    public var meanF0Hz: Double = 0

    public init(date: Date = .now, meanF0Hz: Double) {
        self.date = date
        self.meanF0Hz = meanF0Hz
    }
}

/// A day the app was opened, for the activity calendar. Devices may add the same day; readers dedupe.
@Model
public final class OpenedDay {
    public var day: Date = Date.now

    public init(day: Date) { self.day = day }
}

/// When the person last reset their average pitch. The latest one across devices applies.
@Model
public final class AverageF0Reset {
    public var date: Date = Date.now

    public init(date: Date = .now) { self.date = date }
}

public enum HistorySchema {
    public static let models: [any PersistentModel.Type] = [
        AnalysisRecord.self, PitchSession.self, OpenedDay.self, AverageF0Reset.self,
        CoachAttempt.self, VoiceCheckIn.self, CoachNote.self, CompletedLesson.self, CoachRequest.self,
    ]
    /// At most this many analyses and pitch sessions are kept.
    public static let maximumEntries = 100
}
