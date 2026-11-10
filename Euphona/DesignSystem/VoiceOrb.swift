import SwiftUI

/// The signature visual: liquid pink and blue light flowing inside a glass sphere, whose balance shows
/// how feminine or masculine the voice reads. It flows slowly at rest, brightens and swells with the
/// voice while listening and swirls faster while analyzing.
struct VoiceOrb: View {
    /// Every orb rolls with the same swell. Listening makes it swell with the voice; analyzing rolls faster.
    enum Activity { case resting, listening, thinking }

    /// 0 is fully masculine (blue), 1 fully feminine (pink).
    var balance: Double
    /// Live loudness 0...1 while listening.
    var energy: Double = 0
    var activity: Activity = .resting
    /// The glow around the orb. Off inside lists and other clipping containers, which would cut it
    /// into a visible rectangle; there the page's ambient background carries the color.
    var halo = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    private static let epoch = Date.now

    /// How far the glow reaches from the center, as a fraction of the diameter.
    static let glowReach: CGFloat = 0.78

    /// The voice colors before they lean toward the theme (`ThemeColors`).
    static let basePink = Color(hex: 0xFF8FB3)
    static let baseDeepPink = Color(hex: 0xE75480)
    static let baseBlue = Color(hex: 0x6F9BFF)
    static let baseDeepBlue = Color(hex: 0x3C5FD8)

    /// The surface redraws per frame only while on screen; a resting orb drifts slowly, so 30 fps is enough.
    var body: some View {
        let still = reduceMotion
        TimelineView(.animation(minimumInterval: activity == .resting ? 1.0 / 30 : nil, paused: still || !visible)) { context in
            // Seconds since launch: the shader works in 32-bit floats, which cannot resolve small steps
            // on a reference-date clock.
            let time = still ? 0 : context.date.timeIntervalSince(Self.epoch)
            OrbSurface(balance: balance, energy: energy, time: time * speed)
        }
        .background { if halo { OrbGlow(balance: balance) } }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .scaleEffect(1 + min(max(energy, 0), 1) * 0.07)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: energy)
        .accessibilityHidden(true)
    }

    private var speed: Double {
        switch activity {
        case .resting, .listening: 0.8
        case .thinking: 1.6
        }
    }
}

extension View {
    /// The orb inside a thin, clear Liquid Glass bubble: the glass refracts the glow behind it and
    /// answers a press. For hero orbs that are also controls (Today, recording);
    /// small orbs in lists stay plain.
    /// The orb's glow sits behind the glass, so the bubble refracts it.
    func glassBubble(diameter: CGFloat, balance: Double) -> some View {
        padding(diameter * 0.04)
            .glassEffect(.clear.interactive(), in: .circle)
            .background { OrbGlow(balance: balance).frame(width: diameter, height: diameter) }
    }
}

/// How much larger than on iPhone hero orbs are drawn: the window's size relative to an iPhone's, by the
/// tighter of width and height, between 1 and 1.5. iPad portrait grows the most, landscape and Mac less
/// (height limits them), and Split View or a narrow window falls back to the iPhone size.
enum OrbScale {
    static let phone = CGSize(width: 402, height: 874)
    static let range: ClosedRange<CGFloat> = 1...1.5

    static func forWindow(_ size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(max(min(size.width / phone.width, size.height / phone.height), range.lowerBound), range.upperBound)
    }
}

extension EnvironmentValues {
    /// Set once at the root from the window size (`OrbScale.forWindow`).
    @Entry var orbScale: CGFloat = 1
}

/// The halo: a radial gradient that fades to nothing at `glowReach`, drawn outside the per-frame
/// timeline (it depends only on the balance) and without a blur pass.
struct OrbGlow: View, Animatable {
    var balance: Double
    @Environment(\.theme) private var theme

    var animatableData: Double {
        get { balance }
        set { balance = newValue }
    }

    var body: some View {
        let color = theme.balance(balance)
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let reach = diameter * VoiceOrb.glowReach
            RadialGradient(stops: [
                .init(color: color.opacity(0.5), location: 0.5 / VoiceOrb.glowReach),
                .init(color: color.opacity(0.2), location: 0.72),
                .init(color: color.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: reach)
            .frame(width: reach * 2, height: reach * 2)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

/// One frame of the orb, drawn by the `liquidOrb` Metal shader. Animatable in `balance`, so a score
/// change blends smoothly.
private struct OrbSurface: View, Animatable {
    var balance: Double
    var energy: Double
    var time: Double
    @Environment(\.theme) private var theme

    var animatableData: Double {
        get { balance }
        set { balance = newValue }
    }

    var body: some View {
        Rectangle()
            .visualEffect { [tint = theme.tint] content, proxy in
                content.colorEffect(ShaderLibrary.liquidOrb(
                    .float2(proxy.size), .float(time), .float(balance), .float(min(max(energy, 0), 1)),
                    .color(tint), .float(ThemeColors.harmony)))
            }
            .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    VStack(spacing: 40) {
        VoiceOrb(balance: 0.75).frame(width: 220, height: 220)
        VoiceOrb(balance: 0.25, activity: .thinking).frame(width: 140, height: 140)
    }
    .padding()
}
