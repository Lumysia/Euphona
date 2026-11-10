import Foundation
import SwiftData

/// History operations on SwiftData.
@MainActor
public struct HistoryStore {
    public let context: ModelContext
    public var calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Pinned first, then newest first — the order the cap keeps.
    public static func ordered(_ records: [AnalysisRecord]) -> [AnalysisRecord] {
        let newestFirst = records.sorted { $0.date > $1.date }
        return newestFirst.filter(\.pinned) + newestFirst.filter { !$0.pinned }
    }

    public func analyses() throws -> [AnalysisRecord] {
        Self.ordered(try context.fetch(FetchDescriptor<AnalysisRecord>()))
    }

    @discardableResult
    public func addAnalysis(_ result: EuphonaResult, audio: Data?, audioFormat: String?, date: Date = .now) throws -> AnalysisRecord {
        let record = AnalysisRecord(result: result, date: date, audio: audio, audioFormat: audioFormat)
        context.insert(record)
        for stale in try analyses().dropFirst(HistorySchema.maximumEntries) { context.delete(stale) }
        try context.save()
        return record
    }

    /// The analysis a result is compared with: the latest one before `date` with the same scoring profile.
    /// New results and records from history both use it, so a record
    /// shows the same comparison wherever it is opened.
    public func previousAnalysis(before date: Date, profile: ScoreProfile) throws -> AnalysisRecord? {
        try context.fetch(FetchDescriptor<AnalysisRecord>())
            .filter { $0.date < date && $0.scoreProfile == profile }
            .max { $0.date < $1.date }
    }

    /// Brings every stored overall score in line with today's scoring rules (lists and charts read
    /// the stored score; the result itself is always rescored when opened). Saves only on a change.
    public func rescoreAnalyses() throws {
        var changed = false
        for record in try analyses() {
            guard let result = record.result else { continue }
            changed = record.refresh(from: result) || changed
        }
        if changed { try context.save() }
    }

    public func setPinned(_ record: AnalysisRecord, _ pinned: Bool) throws {
        record.pinned = pinned
        try context.save()
    }

    /// Deletes every stored model. Objects are deleted one by one: batch deletes skip CloudKit, and the
    /// erase has to reach iCloud and the person's other devices.
    public func deleteEverything() throws {
        for model in HistorySchema.models { try deleteAll(model) }
        try context.save()
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws {
        for object in try context.fetch(FetchDescriptor<Model>()) { context.delete(object) }
    }

    public func delete(_ record: AnalysisRecord) throws {
        context.delete(record)
        try context.save()
    }

    /// Analyses since the last average-F0 reset count toward the average, like pitch sessions do.
    public func averageF0ResetDate() throws -> Date? {
        try context.fetch(FetchDescriptor<AverageF0Reset>()).map(\.date).max()
    }

    public func pitchSessions() throws -> [PitchSession] {
        try context.fetch(FetchDescriptor(sortBy: [SortDescriptor(\PitchSession.date, order: .reverse)]))
    }

    public func addPitchSession(meanF0Hz: Double, date: Date = .now) throws {
        guard meanF0Hz.isFinite, meanF0Hz > 0 else { return }
        context.insert(PitchSession(date: date, meanF0Hz: meanF0Hz))
        for stale in try pitchSessions().dropFirst(HistorySchema.maximumEntries) { context.delete(stale) }
        try context.save()
    }

    /// Starts the average pitch over: drops pitch sessions and ignores older analyses.
    public func resetAverageF0(at date: Date = .now) throws {
        for session in try pitchSessions() { context.delete(session) }
        context.insert(AverageF0Reset(date: date))
        try context.save()
    }

    public func recordOpenedDay(_ date: Date = .now) throws {
        let day = calendar.startOfDay(for: date)
        guard try !openedDays().contains(day) else { return }
        context.insert(OpenedDay(day: day))
        try context.save()
    }

    public func openedDays() throws -> Set<Date> {
        Set(try context.fetch(FetchDescriptor<OpenedDay>()).map { calendar.startOfDay(for: $0.day) })
    }

    // MARK: Coach

    public func coachAttempts(goal: VoiceGoal) throws -> [CoachAttempt] {
        let raw = goal.rawValue
        return try context.fetch(FetchDescriptor<CoachAttempt>(predicate: #Predicate { $0.goalRaw == raw }, sortBy: [SortDescriptor(\.date)]))
    }

    @discardableResult
    public func addAttempt(_ exercise: Exercise, metrics: AttemptMetrics, outcome: Outcome, goal: VoiceGoal,
                           date: Date = .now) throws -> CoachAttempt {
        let attempt = CoachAttempt(exercise: exercise, metrics: metrics, outcome: outcome, goal: goal, date: date)
        context.insert(attempt)
        try context.save()
        return attempt
    }

    /// Today's check-in, the latest one if several devices added one.
    public func checkIn(on day: Date = .now, calendar: Calendar = .current) throws -> VoiceCheckIn? {
        let start = calendar.startOfDay(for: day), end = calendar.date(byAdding: .day, value: 1, to: start)!
        var descriptor = FetchDescriptor<VoiceCheckIn>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                      sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func addCheckIn(comfort: Int, pain: Bool, date: Date = .now) throws {
        context.insert(VoiceCheckIn(comfort: comfort, pain: pain, date: date))
        try context.save()
    }

    public func completeLesson(goal: VoiceGoal, date: Date = .now) throws {
        context.insert(CompletedLesson(goal: goal, date: date))
        try context.save()
    }

    public func addNote(_ text: String, exerciseID: String = "", fromLearner: Bool = false, suggestion: PlanRequest? = nil,
                        date: Date = .now) throws {
        context.insert(CoachNote(exerciseID: exerciseID, text: text, fromLearner: fromLearner, suggestion: suggestion, date: date))
        try context.save()
    }

    public func addRequest(_ request: PlanRequest) throws {
        context.insert(CoachRequest(request))
        try context.save()
    }

    /// Today's requests, folded.
    public func requests(on day: Date = .now, calendar: Calendar = .current) throws -> PlanRequests {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let stored = try context.fetch(FetchDescriptor<CoachRequest>(predicate: #Predicate { $0.date >= start && $0.date < end }))
        return PlanRequests(stored.compactMap(\.request), on: day, calendar: calendar)
    }

    public func coachNotes(limit: Int) throws -> [CoachNote] {
        var descriptor = FetchDescriptor<CoachNote>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }
}
