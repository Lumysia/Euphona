import SwiftUI

/// The layout every Practice tool shares: a large live reading, one large card for the instrument,
/// and a Liquid Glass control bar. The same type, spacing and motion on every page keep the four
/// tools one family.
struct InstrumentPanel<Card: View, Controls: View>: View {
    var title: LocalizedStringResource
    var reading: InstrumentReading
    /// Dark cards suit images that read best on black, such as the spectrogram.
    var darkCard = false
    @ViewBuilder var card: Card
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(spacing: 16) {
            reading
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            card
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(darkCard ? Color(hex: 0x0E1220) : .groupedCell,
                            in: .rect(cornerRadius: 28))
                .clipShape(.rect(cornerRadius: 28))
                .environment(\.colorScheme, darkCard ? .dark : colorScheme)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .background(Color.groupedBackground.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) { controls }
            }
            .controlSize(.large)
            .padding(.bottom, 12)
        }
        .navigationTitle(Text(title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @Environment(\.colorScheme) private var colorScheme
}

/// The big number on top of a Practice tool, with its unit and one line of context below.
struct InstrumentReading: View {
    var value: String?
    var unit: String = ""
    /// Shown in place of the number until there is one.
    var symbol: String
    var color: Color = .primary
    var detail: Text

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: value)
                            .scaledFont(size: 64, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(color)
                            .contentTransition(.numericText())
                        if !unit.isEmpty {
                            Text(verbatim: unit).font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .transition(.blurReplace)
                } else {
                    Image(systemName: symbol)
                        .scaledFont(size: 40, weight: .medium)
                        .foregroundStyle(.tertiary)
                        .symbolEffect(.breathe, options: .repeat(.continuous))
                        .transition(.blurReplace)
                }
            }
            .frame(minHeight: 72)
            .animation(.snappy(duration: 0.25), value: value)
            detail
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
        }
        .frame(minHeight: 118)
        .accessibilityElement(children: .combine)
    }
}

/// The main control of a Practice tool: one prominent glass capsule whose symbol and title follow
/// the state.
struct InstrumentPrimaryButton: View {
    var title: LocalizedStringResource
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: symbol).contentTransition(.symbolEffect(.replace)) }
                .font(.headline)
                .padding(.horizontal, 10)
                .frame(minHeight: 52)
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut(.space, modifiers: [])
    }
}

/// A round glass button beside the main control.
struct InstrumentSideButton: View {
    var symbol: String
    var label: LocalizedStringResource
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).frame(width: 52, height: 52)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(label))
        .help(Text(label))
        .transition(.scale.combined(with: .opacity))
    }
}

/// "Rewind 3 seconds" above the control bar while looking back through a recording.
struct ReplayBadge: View {
    var text: Text

    var body: some View {
        text
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }
}

enum NoteName {
    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    static func of(midi: Int) -> String { "\(names[((midi % 12) + 12) % 12])\(midi / 12 - 1)" }

    /// The nearest equal-tempered note to a frequency (A4 = 440 Hz).
    static func of(hz: Double) -> String? {
        guard hz > 0, hz.isFinite else { return nil }
        return of(midi: Int((69 + 12 * log2(hz / 440)).rounded()))
    }
}
