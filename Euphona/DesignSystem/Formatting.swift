import Foundation

/// Every number the app shows goes through these, so digits, separators, units and signs follow the
/// user's locale.
extension Double {
    func formatted(decimals: Int) -> String { formatted(.number.precision(.fractionLength(decimals))) }

    /// "182 Hz"; `signed` writes "+12 Hz" for a change.
    func hertz(decimals: Int = 0, signed: Bool = false) -> String {
        Measurement(value: self, unit: UnitFrequency.hertz).formatted(.measurement(
            width: .abbreviated, usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(decimals)).sign(strategy: signed ? .always(includingZero: false) : .automatic)))
    }

    /// A 0–100 share as "54.3 %" in the locale's style.
    func percent(decimals: Int = 1) -> String {
        (self / 100).formatted(.percent.precision(.fractionLength(decimals)))
    }

    /// A change, always with its sign: "+1.2", "−0.4".
    func change(decimals: Int = 1) -> String {
        formatted(.number.precision(.fractionLength(decimals)).sign(strategy: .always(includingZero: false)))
    }

    /// A position or length as "01:05".
    var clock: String {
        Duration.seconds(Int(max(0, self))).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }
}

/// How a metric's value and its change are written.
enum MetricFormat {
    case score, hertz

    func value(_ value: Double) -> String {
        switch self {
        case .score: value.formatted(decimals: 1)
        case .hertz: value.hertz()
        }
    }

    func change(_ change: Double) -> String {
        switch self {
        case .score: change.change()
        case .hertz: change.hertz(signed: true)
        }
    }

    /// The smallest change worth showing.
    var threshold: Double {
        switch self {
        case .score: 0.05
        case .hertz: 0.5
        }
    }
}
