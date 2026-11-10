import Foundation

/// Something the learner asked the coach for, by a quick reply or in conversation. A request holds
/// for the rest of the day it was made; tomorrow the plan follows the results alone again.
public struct PlanRequest: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// One level down for today's focus.
        case easier
        /// One level up for today's focus.
        case harder
        /// Today's voice should rest: only gentle, unmeasured work.
        case rest
        /// Practise this skill today instead of the path's next one.
        case focus
        /// Drop today's earlier requests.
        case reset
    }

    public var kind: Kind
    /// The skill for `focus`.
    public var skill: Skill?
    public var date: Date

    public init(_ kind: Kind, skill: Skill? = nil, date: Date = .now) {
        self.kind = kind
        self.skill = kind == .focus ? skill : nil
        self.date = date
    }
}

/// Today's requests folded into what the plan does with them.
public struct PlanRequests: Sendable, Equatable {
    /// Levels above (or below) the earned level for the focus skill.
    public var levelShift = 0
    public var focus: Skill?
    public var rest = false

    public static let none = PlanRequests()
    /// The furthest the learner can move away from the earned level in one day.
    public static let maximumShift = 2

    public init() {}

    /// The requests made on `day`, in order; a reset drops the ones before it.
    public init(_ requests: [PlanRequest], on day: Date = .now, calendar: Calendar = .current) {
        for request in requests.sorted(by: { $0.date < $1.date }) where calendar.isDate(request.date, inSameDayAs: day) {
            apply(request)
        }
    }

    /// Adds one more request, made after the others.
    public mutating func apply(_ request: PlanRequest) {
        switch request.kind {
        case .easier: levelShift = max(levelShift - 1, -Self.maximumShift)
        case .harder: levelShift = min(levelShift + 1, Self.maximumShift)
        case .rest: rest = true
        case .focus:
            if request.skill != focus { levelShift = 0 }
            focus = request.skill
        case .reset: self = .none
        }
    }
}
