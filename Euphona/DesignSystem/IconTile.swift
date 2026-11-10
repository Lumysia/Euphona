import SwiftUI

/// A rounded tile in the theme's colors with a white symbol: the face of a tool, a lesson or a step.
struct IconTile: View {
    @Environment(\.theme) private var theme
    var symbol: String
    /// The hue the tile leans toward (`ThemeColors.tile`).
    var accent: Color
    var side: CGFloat = 60
    /// The symbol breathes once when it appears.
    var breathes = false

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.3)
            .fill(.linearGradient(colors: theme.tile(accent), startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: symbol)
                    .scaledFont(size: side * 0.42, weight: .semibold, relativeTo: .title)
                    .foregroundStyle(.white)
                    .symbolEffect(.breathe, options: .nonRepeating, isActive: breathes)
            }
            .accessibilityHidden(true)
    }
}
