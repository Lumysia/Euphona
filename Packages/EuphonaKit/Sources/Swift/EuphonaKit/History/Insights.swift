import Foundation

/// A value-type snapshot of one analysis, so dashboard math can run anywhere and be tested.
public struct AnalysisSample: Sendable, Equatable {
    public var date: Date
    public var finalScore: Double
    public var timbreScore: Double
    public var flowScore: Double
    public var easeScore: Double
    public var speakingF0Hz: Double?
    public var f0VariationHz: Double?

    public init(date: Date, finalScore: Double, timbreScore: Double, flowScore: Double, easeScore: Double,
                speakingF0Hz: Double?, f0VariationHz: Double?) {
        self.date = date
        self.finalScore = finalScore
        self.timbreScore = timbreScore
        self.flowScore = flowScore
        self.easeScore = easeScore
        self.speakingF0Hz = speakingF0Hz
        self.f0VariationHz = f0VariationHz
    }

    @MainActor public init(_ record: AnalysisRecord) {
        self.init(date: record.date, finalScore: record.finalScore, timbreScore: record.timbreScore,
                  flowScore: record.flowScore, easeScore: record.easeScore, speakingF0Hz: record.speakingF0Hz, f0VariationHz: record.f0VariationHz)
    }
}

public enum InsightRange: Int, CaseIterable, Sendable {
    case week = 7, month = 30, quarter = 90, all = 0

    /// Today plus the previous `days - 1` calendar days; `nil` for all time.
    public func start(now: Date, calendar: Calendar) -> Date? {
        guard self != .all else { return nil }
        return calendar.date(byAdding: .day, value: 1 - rawValue, to: calendar.startOfDay(for: now))
    }

    public func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard date <= now else { return false }
        return start(now: now, calendar: calendar).map { date >= $0 } ?? true
    }
}

public enum InsightMetric: CaseIterable, Sendable {
    case composite, pitch, timbre, flow, ease, variation

    public func value(_ sample: AnalysisSample) -> Double? {
        switch self {
        case .composite: sample.finalScore
        case .flow: sample.flowScore
        case .ease: sample.easeScore
        case .pitch: sample.speakingF0Hz
        case .timbre: sample.timbreScore
        case .variation: sample.f0VariationHz
        }
    }

    public var isHertz: Bool { self == .pitch || self == .variation }
}

/// Progress dashboard math.
public enum Insights {
    /// The best analysis of each day (highest overall score, the later one on a tie), oldest first.
    public static func dailyBest(_ samples: [AnalysisSample], calendar: Calendar) -> [AnalysisSample] {
        Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
            .values
            .compactMap { day in
                day.max { ($0.finalScore, $0.date) < ($1.finalScore, $1.date) }
            }
            .sorted { $0.date < $1.date }
    }

    /// The latest value and the mean of the earlier ones.
    public static func latestAndBaseline(_ values: [Double]) -> (latest: Double?, baseline: Double?) {
        guard let latest = values.last else { return (nil, nil) }
        let earlier = values.dropLast()
        return (latest, earlier.isEmpty ? nil : earlier.reduce(0, +) / Double(earlier.count))
    }

    /// Percent change against the baseline; `nil` when it can't be computed or is under 0.5 %.
    public static func percentChange(_ current: Double?, from baseline: Double?) -> Double? {
        guard let current, let baseline, current.isFinite, baseline.isFinite, baseline != 0 else { return nil }
        let change = (current - baseline) / abs(baseline) * 100
        return abs(change) < 0.5 ? nil : change
    }

    /// The average pitch baseline: every pitch session plus every analysis with a pitch, each counted once,
    /// after the last reset.
    public static func averageF0(analyses: [AnalysisSample], sessions: [(date: Date, meanF0Hz: Double)], after reset: Date?) -> Double? {
        let values = analyses.filter { reset.map($0.date.isAfter) ?? true }.compactMap(\.speakingF0Hz)
            + sessions.filter { reset.map($0.date.isAfter) ?? true }.map(\.meanF0Hz)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Consecutive days, ending today (or yesterday if today has no entry yet), that appear in `days`.
    public static func streak(days: Set<Date>, now: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// Chart range for pitch metrics: the data padded by 20 % (at least 1 Hz), never below 0.
    public static func hertzRange(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max((high - low) * 0.2, 1)
        return max(0, low - pad)...(high + pad)
    }
}

private extension Date {
    func isAfter(_ other: Date) -> Bool { self > other }
}
