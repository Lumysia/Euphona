import EuphonaKit
import SwiftUI

/// A GarageBand-style keyboard from C2 to E5, moved an octave at a time. Keys light pink above 165 Hz
/// and blue below; a ribbon above marks the masculine (F♯2–C♯3) and feminine (F♯3–C♯4) ranges. On Mac
/// and iPad with a keyboard, Musical Typing plays it (A–' for notes, Z/X for octaves).
struct PianoView: View {
    @Environment(\.theme) private var theme
    static let keys = Array(36...76)
    static let masculine = 42...49
    static let feminine = 54...61
    /// Musical Typing: home row = white keys, row above = black keys, from C of the current octave.
    private static let typing: [Character: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7, "y": 8, "h": 9, "u": 10, "j": 11,
        "k": 12, "o": 13, "l": 14, "p": 15, ";": 16, "'": 17,
    ]
    static let whiteKeys = keys.filter { !isBlack($0) }

    @State private var synth = PianoSynth()
    @State private var pressed: Set<Int> = []
    @State private var last: Int?
    /// The leftmost visible white key, as an index into `whiteKeys`; starts on C3 so 165 Hz is in view.
    @State private var firstWhite = whiteKeys.firstIndex(of: 48)!
    @State private var visibleWhites = 7
    @FocusState private var focused: Bool

    static func isBlack(_ midi: Int) -> Bool { [1, 3, 6, 8, 10].contains(midi % 12) }
    static func name(_ midi: Int) -> String { NoteName.of(midi: midi) }

    var body: some View {
        InstrumentPanel(title: .pianoTitle, reading: reading) {
            GeometryReader { proxy in
                // Whole keys fill the card: about 44 pt each on iPhone, 56 pt on wider screens.
                let fit = max(5, Int((proxy.size.width / (proxy.size.width > 600 ? 56 : 44)).rounded()))
                let keyWidth = proxy.size.width / CGFloat(fit)
                VStack(alignment: .leading, spacing: 12) {
                    RangeRibbon(keyWidth: keyWidth)
                    PianoKeyboard(keyWidth: keyWidth, height: proxy.size.height - 26 - 12 - 16,
                                  pressed: pressed, press: press, release: release)
                }
                .padding(.top, 16)
                .offset(x: -CGFloat(firstWhite) * keyWidth)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: firstWhite)
                .onChange(of: fit, initial: true) { visibleWhites = fit; clampScroll() }
            }
            // A keyboard runs low to high left to right in every language.
            .environment(\.layoutDirection, .leftToRight)
            .clipped()
        } controls: {
            InstrumentSideButton(symbol: "chevron.left", label: .pianoOctaveDown) { shift(-7) }
                .disabled(firstWhite == 0)
            Text(verbatim: "\(Self.name(Self.whiteKeys[firstWhite])) – \(Self.name(Self.whiteKeys[min(firstWhite + visibleWhites - 1, Self.whiteKeys.count - 1)]))")
                .font(.headline.monospacedDigit())
                .padding(.horizontal, 20)
                .frame(minHeight: 52)
                .glassEffect(.regular, in: .capsule)
                .contentTransition(.numericText())
            InstrumentSideButton(symbol: "chevron.right", label: .pianoOctaveUp) { shift(7) }
                .disabled(firstWhite + visibleWhites >= Self.whiteKeys.count)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: [.down, .up]) { handle($0) }
        .onDisappear { synth.stop() }
    }

    private var reading: InstrumentReading {
        InstrumentReading(
            value: last.map(Self.name), symbol: "pianokeys", color: last.map { theme.pitch(PianoSynth.frequency(midi: $0)) } ?? .primary,
            detail: last.map { Text(verbatim: PianoSynth.frequency(midi: $0).hertz(decimals: 1)) } ?? Text(.pianoSubtitle))
    }

    private func shift(_ whites: Int) {
        firstWhite += whites
        clampScroll()
    }

    private func clampScroll() {
        firstWhite = min(max(firstWhite, 0), max(0, Self.whiteKeys.count - visibleWhites))
    }

    private func press(_ midi: Int) {
        guard Self.keys.contains(midi), !pressed.contains(midi) else { return }
        pressed.insert(midi)
        last = midi
        synth.noteOn(midi)
    }

    private func release(_ midi: Int) {
        pressed.remove(midi)
        synth.noteOff(midi)
    }

    /// Musical Typing starts at the C at or left of the first visible key; Z and X move by octaves.
    private var typingBase: Int { Self.whiteKeys[firstWhite] / 12 * 12 }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard let character = press.characters.lowercased().first else { return .ignored }
        if press.phase == .down, character == "z" { shift(-7); return .handled }
        if press.phase == .down, character == "x" { shift(7); return .handled }
        guard let offset = Self.typing[character] else { return .ignored }
        let midi = typingBase + offset
        if press.phase == .down { self.press(midi) } else { release(midi) }
        return .handled
    }
}

/// The two training ranges, drawn as capsules aligned to their keys.
private struct RangeRibbon: View {
    @Environment(\.theme) private var theme
    var keyWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            band(PianoView.masculine, .orbMasculine, theme.masculineFill)
            band(PianoView.feminine, .orbFeminine, theme.feminineFill)
        }
        .frame(height: 26, alignment: .leading)
    }

    private func band(_ range: ClosedRange<Int>, _ title: LocalizedStringResource, _ color: Color) -> some View {
        let start = PianoKeyboard.x(of: range.lowerBound, keyWidth: keyWidth)
        let end = PianoKeyboard.x(of: range.upperBound, keyWidth: keyWidth) + PianoKeyboard.width(of: range.upperBound, keyWidth: keyWidth)
        return Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color == theme.feminineFill ? Tokens.feminineContent : .white)
            .frame(width: end - start, height: 24)
            .background(color.gradient, in: .capsule)
            .offset(x: start)
    }
}

/// The keys themselves: soft white keys, glossy black keys, a lit key while held.
private struct PianoKeyboard: View {
    var keyWidth: CGFloat
    var height: CGFloat
    var pressed: Set<Int>
    var press: (Int) -> Void
    var release: (Int) -> Void

    static let gap: CGFloat = 2
    private var blackHeight: CGFloat { height * 0.62 }

    /// The note each finger is on, keyed by the key it started on, so a finger slides across keys.
    @State private var fingers: [Int: Int] = [:]

    /// Leading edge of a key; black keys straddle the line between two white keys.
    static func x(of midi: Int, keyWidth: CGFloat) -> CGFloat {
        let whitesBefore = CGFloat(PianoView.keys.filter { $0 < midi && !PianoView.isBlack($0) }.count)
        return PianoView.isBlack(midi) ? whitesBefore * keyWidth - width(of: midi, keyWidth: keyWidth) / 2
                                       : whitesBefore * keyWidth
    }

    static func width(of midi: Int, keyWidth: CGFloat) -> CGFloat {
        PianoView.isBlack(midi) ? keyWidth * 0.58 : keyWidth - gap
    }

    /// The key under a point in the keyboard's space; black keys sit on top.
    private func key(at point: CGPoint) -> Int? {
        guard point.y >= 0, point.y <= height else { return nil }
        func contains(_ midi: Int) -> Bool {
            let x = Self.x(of: midi, keyWidth: keyWidth)
            return point.x >= x && point.x <= x + Self.width(of: midi, keyWidth: keyWidth) + (PianoView.isBlack(midi) ? 0 : Self.gap)
        }
        if point.y <= blackHeight, let black = PianoView.keys.first(where: { PianoView.isBlack($0) && contains($0) }) { return black }
        return PianoView.keys.first { !PianoView.isBlack($0) && contains($0) }
    }

    private func track(_ origin: Int, _ location: CGPoint?) {
        let next = location.flatMap(key(at:))
        let current = fingers[origin]
        guard next != current else { return }
        if let current { release(current) }
        if let next { press(next) }
        fingers[origin] = next
    }

    var body: some View {
        let whites = PianoView.keys.filter { !PianoView.isBlack($0) }
        ZStack(alignment: .topLeading) {
            ForEach(whites, id: \.self) { midi in
                PianoKey(midi: midi, black: false, down: pressed.contains(midi), track: track, press: press, release: release)
                    .frame(width: Self.width(of: midi, keyWidth: keyWidth), height: height)
                    .offset(x: Self.x(of: midi, keyWidth: keyWidth))
            }
            ForEach(PianoView.keys.filter(PianoView.isBlack), id: \.self) { midi in
                PianoKey(midi: midi, black: true, down: pressed.contains(midi), track: track, press: press, release: release)
                    .frame(width: Self.width(of: midi, keyWidth: keyWidth), height: blackHeight)
                    .offset(x: Self.x(of: midi, keyWidth: keyWidth))
            }
        }
        .frame(width: CGFloat(PianoView.whiteKeys.count) * keyWidth, height: height, alignment: .topLeading)
        .coordinateSpace(.named(Self.space))
    }

    static let space = "keyboard"
}

private struct PianoKey: View {
    @Environment(\.theme) private var theme
    var midi: Int
    var black: Bool
    var down: Bool
    /// Where this key's finger is in the keyboard (nil when lifted).
    var track: (Int, CGPoint?) -> Void
    var press: (Int) -> Void
    var release: (Int) -> Void
    @State private var hovering = false

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: black ? 6 : 9, bottomTrailingRadius: black ? 6 : 9)
        let lit = theme.pitch(PianoSynth.frequency(midi: midi))
        shape
            .fill(black ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3A3A3C), Color(hex: 0x0E0E10)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(LinearGradient(colors: [.white, Color(hex: 0xF1F1F4)], startPoint: .top, endPoint: .bottom)))
            .overlay { if down { shape.fill(lit.gradient.opacity(black ? 0.9 : 0.75)) } }
            .overlay { if hovering && !down { shape.fill(.primary.opacity(black ? 0.12 : 0.05)) } }
            .overlay(alignment: .top) {
                if black {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.18)).frame(height: 10).padding(.horizontal, 4).padding(.top, 3)
                }
            }
            .overlay { shape.strokeBorder(.black.opacity(black ? 0.6 : 0.12), lineWidth: 0.8) }
            .overlay(alignment: .bottom) {
                if !black && midi % 12 == 0 {
                    Text(verbatim: PianoView.name(midi)).font(.caption2.weight(.semibold))
                        .foregroundStyle(down ? .white : .secondary).padding(.bottom, 10)
                }
            }
            .shadow(color: down ? lit.opacity(0.6) : .black.opacity(black ? 0.35 : 0.12), radius: down ? 10 : 3, y: down ? 0 : 2)
            .offset(y: down ? 2 : 0)
            .animation(.easeOut(duration: 0.06), value: down)
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(PianoKeyboard.space))
                .onChanged { track(midi, $0.location) }
                .onEnded { _ in track(midi, nil) })
            .onHover { hovering = $0 }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: PianoView.name(midi)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { press(midi); release(midi) }
            .zIndex(black ? 1 : 0)
    }
}
