import SwiftUI

/// How the voice feels, from 1 (sore) to 5 (fresh), as five large choices.
struct ComfortPicker: View {
    @Binding var comfort: Int?

    static let levels: [(title: LocalizedStringResource, symbol: String)] = [
        (.coachComfort1, "cloud.rain"), (.coachComfort2, "cloud"), (.coachComfort3, "cloud.sun"),
        (.coachComfort4, "sun.max"), (.coachComfort5, "sparkles"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(Self.levels.enumerated()), id: \.offset) { index, level in
                let selected = comfort == index + 1
                Button { comfort = index + 1 } label: {
                    VStack(spacing: 8) {
                        Image(systemName: level.symbol).font(.title2).symbolVariant(selected ? .fill : .none)
                        Text(level.title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(Color.groupedCell),
                                in: .rect(cornerRadius: 18))
                    .contentShape(.rect(cornerRadius: 18))
                }
                .buttonStyle(.card)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: comfort)
    }
}
