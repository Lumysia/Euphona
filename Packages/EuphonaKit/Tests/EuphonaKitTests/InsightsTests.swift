import Foundation
import Testing
@testable import EuphonaKit

struct InsightsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func streaksCountDaysInARowAndSurviveUntilTheNextDayEnds() {
        let day = { (offset: Double) in now.addingTimeInterval(-offset * 86_400) }
        let three = Streak(activity: [day(0), day(1), day(1), day(2), day(4)], today: now, calendar: calendar)
        #expect(three.days == 3 && three.activeToday)
        #expect(three.week == [false, false, true, false, true, true, true])
        // Nothing yet today: yesterday's streak still stands.
        let pending = Streak(activity: [day(1), day(2)], today: now, calendar: calendar)
        #expect(pending.days == 2 && !pending.activeToday)
        #expect(Streak(activity: [day(2)], today: now, calendar: calendar).days == 0)
        #expect(Streak.extends(at: now, activity: [day(1), now], calendar: calendar))
        #expect(!Streak.extends(at: now, activity: [now.addingTimeInterval(-60), now], calendar: calendar))
    }

    func sample(_ daysAgo: Double, score: Double, f0: Double? = 180) -> AnalysisSample {
        AnalysisSample(date: now.addingTimeInterval(-daysAgo * 86_400), finalScore: score, timbreScore: 50,
                       flowScore: 60, easeScore: 90, speakingF0Hz: f0, f0VariationHz: nil)
    }

    @Test func weekIncludesTodayAndSixDaysBefore() {
        let start = InsightRange.week.start(now: now, calendar: calendar)!
        #expect(calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day == 6)
        #expect(!InsightRange.week.contains(now.addingTimeInterval(60), now: now, calendar: calendar))
    }

    @Test func dailyBestKeepsTheHighestScorePerDay() {
        let best = Insights.dailyBest([sample(0, score: 40), sample(0.01, score: 70), sample(1, score: 10)], calendar: calendar)
        #expect(best.map(\.finalScore) == [10, 70])
    }

    @Test func changeIsHiddenUnderHalfAPercent() {
        #expect(Insights.percentChange(100.4, from: 100) == nil)
        #expect(Insights.percentChange(110, from: 100) == 10)
        #expect(Insights.percentChange(5, from: 0) == nil)
    }

    @Test func averagePitchCountsSessionsAndAnalysesAfterTheReset() {
        let reset = now.addingTimeInterval(-2 * 86_400)
        let average = Insights.averageF0(analyses: [sample(1, score: 0, f0: 200), sample(3, score: 0, f0: 100), sample(1, score: 0, f0: nil)],
                                         sessions: [(now, 180)], after: reset)
        #expect(average == 190)
    }

    @Test func streakCountsBackFromToday() {
        let today = calendar.startOfDay(for: now)
        let days: Set<Date> = [today, today.addingTimeInterval(-86_400), today.addingTimeInterval(-3 * 86_400)]
        #expect(Insights.streak(days: days, now: now, calendar: calendar) == 2)
    }
}
