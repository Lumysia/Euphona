import EuphonaKit
import SwiftUI

/// What to work on next: the component that costs the most points.
extension ScoreBreakdown {
    var focusTitle: LocalizedStringResource {
        switch bottleneck {
        case nil: .scoreFocusNoneTitle
        case .timbre: .scoreFocusTimbreTitle
        case .f0: .scoreFocusPitchTitle
        case .flow: .scoreFocusFlowTitle
        case .ease: .scoreFocusEaseTitle
        }
    }

    var focusGuidance: LocalizedStringResource {
        switch bottleneck {
        case nil: .scoreFocusNone
        case .timbre: pitch == nil ? .scoreFocusTimbreNoPitch : .scoreFocusTimbre
        case .f0: .scoreFocusPitch
        case .flow: .scoreFocusFlow
        case .ease: .scoreFocusEase
        }
    }
}

extension ScoreMetric {
    var title: LocalizedStringResource {
        switch self {
        case .timbre: .timbreTitle
        case .flow: .scoreComponentFlow
        case .ease: .scoreComponentEase
        case .f0: .pitchTitle
        }
    }

    var symbol: String {
        switch self {
        case .timbre: "waveform"
        case .flow: "metronome"
        case .ease: "leaf"
        case .f0: "tuningfork"
        }
    }
}
