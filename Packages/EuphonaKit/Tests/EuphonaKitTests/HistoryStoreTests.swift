import Foundation
import SwiftData
import Testing
@testable import EuphonaKit

@MainActor
struct HistoryStoreTests {
    let store: HistoryStore

    init() throws {
        let container = try ModelContainer(
            for: Schema(HistorySchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        store = HistoryStore(context: ModelContext(container))
    }

    /// A result whose timbre (and so its overall score) differs by `final`.
    static func result(final: Double) throws -> EuphonaResult {
        var result = sampleResult
        result.timbre.score = final
        return result
    }

    @Test func keepsPinnedAndNewestWithinTheCap() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let pinned = try store.addAnalysis(try Self.result(final: 1), audio: nil, audioFormat: nil, date: start)
        try store.setPinned(pinned, true)
        for index in 1...HistorySchema.maximumEntries {
            try store.addAnalysis(try Self.result(final: Double(index)), audio: nil, audioFormat: nil,
                                  date: start.addingTimeInterval(Double(index)))
        }
        let kept = try store.analyses()
        #expect(kept.count == HistorySchema.maximumEntries)
        #expect(kept.first?.pinned == true)
        #expect(kept[1].timbreScore == Double(HistorySchema.maximumEntries))
        #expect(!kept.contains { !$0.pinned && $0.timbreScore == 1 })
    }

    @Test func comparesWithTheLatestEarlierAnalysisOfTheSameProfile() throws {
        let start = Date(timeIntervalSince1970: 2_000_000)
        func add(_ final: Double, minutes: Double, profile: ScoreProfile = .feminization) throws -> AnalysisRecord {
            var result = try Self.result(final: final)
            result.scoreProfile = profile
            return try store.addAnalysis(result, audio: nil, audioFormat: nil, date: start.addingTimeInterval(minutes * 60))
        }
        let first = try add(40, minutes: 0)
        _ = try add(55, minutes: 10, profile: .masculinization)
        let second = try add(60, minutes: 20)
        let third = try add(70, minutes: 30)

        #expect(try store.previousAnalysis(before: first.date, profile: .feminization) == nil)
        #expect(try store.previousAnalysis(before: second.date, profile: .feminization)?.timbreScore == 40)
        #expect(try store.previousAnalysis(before: third.date, profile: .feminization)?.timbreScore == 60)
        #expect(try store.previousAnalysis(before: third.date, profile: .masculinization)?.timbreScore == 55)
    }

    @Test func rescoringFollowsTheRules() throws {
        let record = try store.addAnalysis(try Self.result(final: 50), audio: nil, audioFormat: nil)
        record.finalScore = 1
        try store.rescoreAnalyses()
        #expect(record.finalScore == record.result?.composite.finalScore)
    }

    @Test func erasesEveryKindOfRecord() throws {
        try store.addAnalysis(try Self.result(final: 50), audio: Data([1]), audioFormat: "m4a")
        try store.addPitchSession(meanF0Hz: 180)
        try store.resetAverageF0()
        try store.recordOpenedDay()
        try store.deleteEverything()
        for model in HistorySchema.models {
            #expect(try count(model) == 0, "\(model)")
        }
    }

    private func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        try store.context.fetchCount(FetchDescriptor<Model>())
    }

    @Test func settingsResetReturnsToOnboardingAndDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "reset-\(UUID())"))
        let settings = AppSettings(defaults: defaults)
        settings.completeOnboarding(goal: .masculine, syncsWithICloud: false, coachModel: .off)
        settings.customPassage = "hello"
        settings.gapThresholdMs = 500
        settings.reset()
        #expect(!settings.hasCompletedOnboarding)
        #expect(settings.voiceGoal == .feminine && settings.customPassage.isEmpty && settings.gapThresholdMs == AppSettings.defaultGapMs)
        #expect(settings.syncsWithICloud && settings.coachModel == .onDevice)
        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.hasCompletedOnboarding && reloaded.customPassage.isEmpty)
    }

    @Test func storesTheResultForDetailViews() throws {
        let record = try store.addAnalysis(try Self.result(final: 42), audio: Data([1, 2]), audioFormat: "m4a")
        #expect(record.result?.timbre.score == 42)
        #expect(record.finalScore == record.result?.composite.finalScore)
        #expect(record.scoreProfile == .feminization)
        // The median of the voiced windows: the 260 Hz squeal doesn't pull it up.
        #expect(record.speakingF0Hz == 184)
    }

    @Test func resetDropsPitchSessions() throws {
        try store.addPitchSession(meanF0Hz: 170)
        try store.addPitchSession(meanF0Hz: .nan)
        #expect(try store.pitchSessions().count == 1)
        let reset = Date()
        try store.resetAverageF0(at: reset)
        #expect(try store.pitchSessions().isEmpty)
        #expect(try store.averageF0ResetDate() == reset)
    }

    @Test func recordsEachDayOnce() throws {
        let morning = Date(timeIntervalSince1970: 1_700_000_000)
        try store.recordOpenedDay(morning)
        try store.recordOpenedDay(morning.addingTimeInterval(3600))
        #expect(try store.openedDays().count == 1)
    }
}

/// A minimal result: one speech segment, one embedding window.
let sampleResult = EuphonaResult(
    modelVersion: "test", scoreProfile: .feminization, inputSeconds: 6,
    speech: .init(seconds: 5.5, segments: [.init(startSeconds: 0.2, endSeconds: 5.7, speechStartSeconds: 0, speechEndSeconds: 5.5)]),
    f0: .init(standardDeviationHz: 20.1, windows: [
        .init(startSeconds: 0.2, endSeconds: 0.25, f0Hz: 180), .init(startSeconds: 0.25, endSeconds: 0.3, f0Hz: nil),
        .init(startSeconds: 0.3, endSeconds: 0.35, f0Hz: 184), .init(startSeconds: 0.35, endSeconds: 0.4, f0Hz: 260),
    ]),
    timbre: .init(score: 60, windows: [.init(startSeconds: 0.2, endSeconds: 1.715, score: 60)]),
    flow: .init(score: 85, articulationRate: 4.2, pauseShare: 0.1),
    ease: 90,
    hnrDb: 18)
