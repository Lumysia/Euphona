import SwiftUI

/// Pointer feedback for custom tappable cards: a lift on iPad, a soft highlight and the pointing hand
/// on Mac. System controls and list rows already handle this themselves.
struct HoverCard: ViewModifier {
    var cornerRadius: CGFloat
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.primary.opacity(hovering ? 0.05 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(hovering && !reduceMotion ? 1.01 : 1)
            .animation(.smooth(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
            #if os(iOS)
            .contentShape(.hoverEffect, .rect(cornerRadius: cornerRadius))
            .hoverEffect(.lift)
            #else
            .pointerStyle(.link)
            #endif
    }
}

extension View {
    func hoverCard(cornerRadius: CGFloat = 24) -> some View { modifier(HoverCard(cornerRadius: cornerRadius)) }
}

/// Keeps a scrolling list full width, so its scroll bar stays at the window's edge, and centers its rows
/// in at most `width` points (never closer to the edge than the system's inset).
struct ReadableContentWidth: ViewModifier {
    static let minimumMargin: CGFloat = 20
    var width: CGFloat
    @State private var margin = ReadableContentWidth.minimumMargin

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { max(Self.minimumMargin, ($0.size.width - width) / 2) } action: { margin = $0 }
    }
}

extension View {
    func readableContentWidth(_ width: CGFloat) -> some View { modifier(ReadableContentWidth(width: width)) }
}

/// Custom cards that navigate: they dip the moment a finger lands and spring back on release, the way
/// system buttons highlight on touch-down, so a tap feels answered before the page changes.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(configuration.isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.3, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var card: PressableCardStyle { PressableCardStyle() }
}

/// A disclosure group whose whole row toggles it. On Mac only the small chevron toggles a plain
/// `DisclosureGroup` in a form, so its label read as text that could not be opened.
struct RowDisclosureGroup<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded, content: content) {
            #if os(macOS)
            Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                label().frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            #else
            label()
            #endif
        }
    }
}
