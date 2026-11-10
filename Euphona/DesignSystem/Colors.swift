import EuphonaKit
import SwiftUI

extension Color {
    /// The page behind grouped lists, for screens that draw their own background under one.
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// A card on the grouped background: white in light mode, raised gray in dark, like a list's rows.
    static var groupedCell: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    nonisolated init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that follows the system appearance. Nonisolated: the system may resolve it off the main thread.
    nonisolated init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #endif
    }
}

/// The six theme palettes. The palette's color is the app tint; backgrounds and materials stay with
/// the system.
extension ThemePaletteID {
    private var tintHex: (light: UInt32, dark: UInt32) {
        switch self {
        case .coral: (0xD96A3E, 0xFFB59A)
        case .rose: (0xA63D64, 0xFFABC7)
        case .ocean: (0x006A6A, 0x72D8D2)
        case .forest: (0x3D6B35, 0xA5D39B)
        case .indigo: (0x4A5AAE, 0xB8C3FF)
        case .amber: (0x805500, 0xF7BD5D)
        }
    }

    var tint: Color { Color(light: tintHex.light, dark: tintHex.dark) }
    /// The tint deep enough under white symbols in either appearance, for icon tiles.
    var deepTint: Color { Color(hex: tintHex.light) }

    var title: LocalizedStringResource {
        switch self {
        case .coral: .themeCoral
        case .rose: .themeRose
        case .ocean: .themeOcean
        case .forest: .themeForest
        case .indigo: .themeIndigo
        case .amber: .themeAmber
        }
    }
}

/// The voice colors fitted to the theme: each fixed color leans a little toward the theme tint, so pink
/// still reads as feminine and blue as masculine while every page sits in one family of colors.
/// Read it from the environment (`\.theme`), set at the root from the chosen palette.
struct ThemeColors {
    /// How far each voice color leans toward the tint.
    static let harmony = 0.15

    let tint: Color
    let deepTint: Color
    /// Colors for the score components besides pitch (which stays pink), picked per palette to stay
    /// clear of its tint.
    let flow: Color
    let ease: Color
    let timbre: Color
    let variation: Color

    init(_ palette: ThemePaletteID) {
        tint = palette.tint
        deepTint = palette.deepTint
        let green = Color(hex: 0x2F8F5B), purple = Color(hex: 0x8B6FD6), amber = Color(hex: 0xC98A3C), teal = Color(hex: 0x25A6A0)
        let cornflower = Color(hex: 0x4F7FD0)
        (flow, ease, timbre, variation) = switch palette {
        case .coral: (green, amber, purple, teal)
        case .rose: (green, teal, purple, amber)
        case .ocean: (Color(hex: 0x6A9A2E), cornflower, purple, amber)
        case .forest: (teal, cornflower, purple, amber)
        case .indigo: (green, teal, Color(hex: 0xB45FC0), amber)
        case .amber: (green, cornflower, purple, teal)
        }
    }

    private func fit(_ color: Color) -> Color { color.mix(with: tint, by: Self.harmony, in: .perceptual) }

    /// How far an icon tile's far corner leans from the deep tint toward the tool's own accent.
    static let tileLean = 0.4

    /// An icon tile's gradient: the theme's deep tint, leaning toward `accent` at the far corner, so
    /// every tile reads as the theme while each tool keeps a hue of its own.
    func tile(_ accent: Color) -> [Color] {
        [deepTint, deepTint.mix(with: accent, by: Self.tileLean, in: .perceptual)]
    }

    var pink: Color { fit(VoiceOrb.basePink) }
    var deepPink: Color { fit(VoiceOrb.baseDeepPink) }
    var blue: Color { fit(VoiceOrb.baseBlue) }
    var deepBlue: Color { fit(VoiceOrb.baseDeepBlue) }
    /// Light fills for feminine and masculine regions.
    var feminineFill: Color { fit(Tokens.feminine) }
    var masculineFill: Color { fit(Tokens.masculine) }
    var feminineInk: Color { fit(Tokens.feminineInk) }
    var masculineInk: Color { fit(Tokens.masculineInk) }
    var teal: Color { fit(Tokens.insightTeal) }
    var purple: Color { fit(Tokens.insightPurple) }

    /// The one color for a balance (0 masculine, 1 feminine), mixed in the perceptual space: the orb's
    /// glow, the ambient page tint and the charts all use it, so a balance looks the same everywhere.
    func balance(_ balance: Double) -> Color {
        blue.mix(with: pink, by: min(max(balance, 0), 1), in: .perceptual)
    }

    /// Pitch above the midpoint in pink, below it in blue, as text and lines.
    func pitch(_ hz: Double) -> Color { hz > Scoring.pitchMidpointHz ? feminineInk : masculineInk }
}

extension EnvironmentValues {
    @Entry var theme = ThemeColors(.coral)
}

/// Fixed semantic colors.
enum Tokens {
    static let feminine = Color(hex: 0xFFB6C1)
    static let feminineContent = Color(hex: 0x3A1F2A)
    static let masculine = Color(hex: 0x6495ED)
    static let spectrumPink = Color(hex: 0xE75480)
    static let success = Color(light: 0x1F6F43, dark: 0xB8E6C6)
    static let danger = Color(light: 0x8E1B2E, dark: 0xFFD6DC)
    static let warning = Color(hex: 0xF08C32)
    static let insightTeal = Color(hex: 0x25A6A0)
    static let insightPurple = Color(hex: 0x8B6FD6)
    static let spectrumAxis = Color(hex: 0xB9C2D0)
    static let neutralScore = Color(hex: 0x9CA3AF)
    // Score bands, readable as text on light and dark backgrounds (deeper in light mode).
    static let scoreLow = Color(light: 0xC23B4C, dark: 0xFF8A96)
    static let scoreLowMid = Color(light: 0xC35A1C, dark: 0xFFA066)
    static let scoreMid = Color(light: 0x8F7100, dark: 0xF2CF55)
    static let scoreHighMid = Color(light: 0x2E8A52, dark: 0x7FD29C)
    static let scoreHigh = Color(light: 0x0F7A70, dark: 0x5ED6C6)
    /// Pitch above and below the 165 Hz line, as text and lines (the light fills stay `feminine`/`masculine`).
    static let feminineInk = Color(light: 0xC93C76, dark: 0xFF9EC4)
    static let masculineInk = Color(light: 0x3A63D8, dark: 0x8FB0FF)
}
