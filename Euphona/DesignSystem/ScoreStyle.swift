import EuphonaKit
import SwiftUI

extension Tokens {
    /// Score colors in 20-point bands.
    static func scoreColor(_ score: Double) -> Color {
        switch score {
        case ..<20: scoreLow
        case ..<40: scoreLowMid
        case ..<60: scoreMid
        case ..<80: scoreHighMid
        default: scoreHigh
        }
    }
}


