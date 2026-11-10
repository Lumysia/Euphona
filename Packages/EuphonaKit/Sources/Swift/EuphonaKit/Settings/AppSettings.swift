import Foundation
import Observation

/// The voice the person is training towards. Decides the score profile.
public enum VoiceGoal: String, CaseIterable, Sendable, Codable {
    case masculine
    case feminine

    public var scoreProfile: ScoreProfile {
        switch self {
        case .feminine: .feminization
        case .masculine: .masculinization
        }
    }
}

public enum ThemePaletteID: String, CaseIterable, Sendable {
    case coral, rose, ocean, forest, indigo, amber
}

public enum PitchChartStyle: String, CaseIterable, Sendable {
    case curve, dots
}

/// Which language model reviews coach attempts; `off` uses the written coach only.
public enum CoachModelChoice: String, CaseIterable, Sendable {
    case onDevice, privateCloud, off
}

public enum PassageSource: String, CaseIterable, Sendable {
    case official, custom
}

/// Device-local preferences.
@MainActor @Observable
public final class AppSettings {
    public static let onboardingVersion = 4
    public static let gapRange = 50...1000
    public static let defaultGapMs = 200
    public static let f0SampleRateRange = 20...60
    public static let defaultF0SampleRate = 30

    @ObservationIgnored private let defaults: UserDefaults

    public var voiceGoal: VoiceGoal { didSet { store(voiceGoal.rawValue, .voiceGoal) } }
    public var completedOnboardingVersion: Int { didSet { store(completedOnboardingVersion, .onboarding) } }
    public var palette: ThemePaletteID { didSet { store(palette.rawValue, .palette) } }
    public var passageSource: PassageSource { didSet { store(passageSource.rawValue, .passageSource) } }
    public var officialPassageIndex: Int { didSet { store(officialPassageIndex, .officialPassage) } }
    public var customPassage: String { didSet { store(customPassage, .customPassage) } }
    public var pitchChartStyle: PitchChartStyle { didSet { store(pitchChartStyle.rawValue, .chartStyle) } }
    public var gapThresholdMs: Int { didSet { store(gapThresholdMs, .gap) } }
    public var f0SampleRate: Int { didSet { store(f0SampleRate, .f0Rate) } }
    public var analyzer: AnalyzerSettings { didSet { storeAnalyzer() } }
    /// History is kept in the user's private iCloud database; off keeps it on this device only.
    public var syncsWithICloud: Bool { didSet { store(syncsWithICloud, .iCloudSync) } }
    /// Live pitch shows the voice goal's typical band.
    public var showsPitchTarget: Bool { didSet { store(showsPitchTarget, .pitchTarget) } }
    public var coachModel: CoachModelChoice { didSet { store(coachModel.rawValue, .coachModel) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceGoal = defaults.string(forKey: Key.voiceGoal.rawValue).flatMap(VoiceGoal.init) ?? .feminine
        completedOnboardingVersion = defaults.integer(forKey: Key.onboarding.rawValue)
        palette = defaults.string(forKey: Key.palette.rawValue).flatMap(ThemePaletteID.init) ?? .coral
        passageSource = defaults.string(forKey: Key.passageSource.rawValue).flatMap(PassageSource.init) ?? .official
        officialPassageIndex = defaults.integer(forKey: Key.officialPassage.rawValue)
        customPassage = defaults.string(forKey: Key.customPassage.rawValue) ?? ""
        pitchChartStyle = defaults.string(forKey: Key.chartStyle.rawValue).flatMap(PitchChartStyle.init) ?? .curve
        gapThresholdMs = (defaults.object(forKey: Key.gap.rawValue) as? Int ?? Self.defaultGapMs).clamped(to: Self.gapRange)
        f0SampleRate = (defaults.object(forKey: Key.f0Rate.rawValue) as? Int ?? Self.defaultF0SampleRate)
            .clamped(to: Self.f0SampleRateRange)
        analyzer = Self.loadAnalyzer(defaults)
        syncsWithICloud = defaults.object(forKey: Key.iCloudSync.rawValue) as? Bool ?? true
        showsPitchTarget = defaults.object(forKey: Key.pitchTarget.rawValue) as? Bool ?? true
        coachModel = defaults.string(forKey: Key.coachModel.rawValue).flatMap(CoachModelChoice.init) ?? .onDevice
    }

    public var hasCompletedOnboarding: Bool { completedOnboardingVersion >= Self.onboardingVersion }

    public func completeOnboarding(goal: VoiceGoal, syncsWithICloud: Bool, coachModel: CoachModelChoice) {
        voiceGoal = goal
        self.syncsWithICloud = syncsWithICloud
        self.coachModel = coachModel
        completedOnboardingVersion = Self.onboardingVersion
    }

    public func resetAnalyzer() { analyzer = .standard }

    /// Clamps analyzer settings to their ranges, keeping the F0 limits apart.
    public static func validated(_ settings: AnalyzerSettings) -> AnalyzerSettings {
        let range = AnalyzerSettings.f0Range
        let gap = AnalyzerSettings.minimumF0Span
        var result = settings
        result.threads = settings.threads.clamped(to: 1...AnalyzerSettings.maximumThreads)
        result.minF0Hz = settings.minF0Hz.clamped(to: range.lowerBound...(range.upperBound - gap))
        result.maxF0Hz = max(settings.maxF0Hz.clamped(to: (range.lowerBound + gap)...range.upperBound), result.minF0Hz + gap)
        result.minConfidence = settings.minConfidence.clamped(to: AnalyzerSettings.confidenceRange)
        return result
    }

    /// Forgets every setting (onboarding included) and returns to the defaults (which are then stored).
    public func reset() {
        for key in Key.allCases { defaults.removeObject(forKey: key.rawValue) }
        let fresh = AppSettings(defaults: defaults)
        voiceGoal = fresh.voiceGoal
        completedOnboardingVersion = fresh.completedOnboardingVersion
        palette = fresh.palette
        passageSource = fresh.passageSource
        officialPassageIndex = fresh.officialPassageIndex
        customPassage = fresh.customPassage
        pitchChartStyle = fresh.pitchChartStyle
        gapThresholdMs = fresh.gapThresholdMs
        f0SampleRate = fresh.f0SampleRate
        analyzer = fresh.analyzer
        syncsWithICloud = fresh.syncsWithICloud
        showsPitchTarget = fresh.showsPitchTarget
        coachModel = fresh.coachModel
    }

    private enum Key: String, CaseIterable {
        case voiceGoal, onboarding, palette, passageSource, officialPassage, customPassage, chartStyle, gap, f0Rate
        case analyzer, iCloudSync, pitchTarget, coachModel
    }

    private func store(_ value: Any, _ key: Key) { defaults.set(value, forKey: key.rawValue) }

    private func storeAnalyzer() {
        let valid = Self.validated(analyzer)
        if valid != analyzer { analyzer = valid; return }
        defaults.set(try? JSONEncoder().encode(analyzer), forKey: Key.analyzer.rawValue)
    }

    private static func loadAnalyzer(_ defaults: UserDefaults) -> AnalyzerSettings {
        guard let data = defaults.data(forKey: Key.analyzer.rawValue),
              let stored = try? JSONDecoder().decode(AnalyzerSettings.self, from: data)
        else { return .standard }
        return validated(stored)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
