import Foundation

/// Days in a row with practice: a full analysis or a finished coach lesson (a rest lesson included, so
/// resting a tired voice never breaks the streak). A streak still counts until the end of the day after
/// its last active day.
public struct Streak: Sendable, Equatable {
    /// Consecutive active days ending today, or yesterday when today has nothing yet.
    public var days: Int
    public var activeToday: Bool
    /// The last seven days, oldest first, today last.
    public var week: [Bool]

    public init(activity dates: [Date], today: Date = .now, calendar: Calendar = .current) {
        let active = Set(dates.map { calendar.startOfDay(for: $0) })
        let start = calendar.startOfDay(for: today)
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: -offset, to: start)! }
        activeToday = active.contains(start)
        var count = 0
        var offset = activeToday ? 0 : 1
        while active.contains(day(offset)) {
            count += 1
            offset += 1
        }
        days = count
        week = (0..<7).reversed().map { active.contains(day($0)) }
    }

    /// Whether the activity at `date` was the day's first, so it is what extended the streak.
    public static func extends(at date: Date, activity dates: [Date], calendar: Calendar = .current) -> Bool {
        !dates.contains { $0 < date && calendar.isDate($0, inSameDayAs: date) }
    }
}
