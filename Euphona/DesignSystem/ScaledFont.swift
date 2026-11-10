import SwiftUI

/// A system font at a designed point size that still follows Dynamic Type, scaling with the given
/// text style. For hero numbers and symbols that the text styles don't cover.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: style))
    }
}
