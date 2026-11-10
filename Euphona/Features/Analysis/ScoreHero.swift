import EuphonaKit
import SwiftUI

/// The result's hero: the voice orb shows how the voice reads while the score counts up to a
/// rising chime (`ResultChime`).
struct ScoreHero: View {
    @Environment(\.theme) private var theme
    static let duration = 0.9
    static let delay = 0.5
    static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1))

    var score: Double
    var previousScore: Double?
    /// `EuphonaResult.voiceBalance`.
    var balance: Double
    /// Count up from the previous score with sound; false shows the score at once.
    var animate: Bool
    /// The orb's size on iPhone; larger windows scale it by `orbScale`.
    var baseOrbSize: CGFloat = 220
    /// Called when the count-up ends (or is cut off), so the owner can keep a recreated hero from replaying it.
    var onReveal: () -> Void = {}

    @State private var shown: Double?
    @State private var appeared = false
    @State private var chime = ResultChime()
    @Environment(\.orbScale) private var orbScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var orbSize: CGFloat { baseOrbSize * orbScale }

    var body: some View {
        let target = min(max(score, 0), 100)
        let value = shown ?? target
        let feminine = balance * 100
        VStack(spacing: 18) {
            VoiceOrb(balance: balance, halo: false)
                .frame(width: orbSize, height: orbSize)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 2) {
                Text(verbatim: value.formatted(decimals: 1))
                    .scaledFont(size: 64, weight: .heavy, design: .rounded)
                    .monospacedDigit()
                Text(.scoreFinalScore).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                BalancePill(label: .orbFeminine, value: feminine, color: theme.deepPink)
                BalancePill(label: .orbMasculine, value: 100 - feminine, color: theme.deepBlue)
            }
        }
        .onAppear {
            if animate {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) { appeared = true }
            } else {
                appeared = true
            }
        }
        .task(id: target) { await run(to: target) }
        .onDisappear { chime.stop() }
        .sensoryFeedback(.success, trigger: shown == target && animate)
        .accessibilityElement(children: .combine)
    }

    /// Counts the score up frame by frame while the chime climbs one scale step at a time from the
    /// previous score's note to this one's (falling if the score fell), then lands on it.
    private func run(to target: Double) async {
        let start = animate ? min(max(previousScore ?? 0, 0), 100) : target
        shown = start
        guard animate else { return }
        defer { onReveal() }
        do { try await Task.sleep(for: .seconds(Self.delay)) } catch { return }
        let first = ResultChime.step(start), last = ResultChime.step(target)
        let notes = abs(last - first) + 1
        // Notes spread over the count-up, slowing toward the end like the number.
        let noteTimes = (0..<notes).map { index in
            notes == 1 ? 0 : Self.duration * 0.85 * Self.curve.inverse.value(at: Double(index) / Double(notes - 1))
        }
        let began = ContinuousClock.now
        var nextNote = 0
        while !Task.isCancelled {
            let elapsed = (ContinuousClock.now - began) / .seconds(1)
            let progress = min(elapsed / Self.duration, 1)
            shown = start + (target - start) * Self.curve.value(at: progress)
            while nextNote < notes, noteTimes[nextNote] <= elapsed {
                let step = first + (last >= first ? nextNote : -nextNote)
                if nextNote == notes - 1 { chime.land(step: step) } else { chime.play(step: step, loudness: 0.45 + 0.4 * Double(nextNote) / Double(notes)) }
                nextNote += 1
            }
            if progress >= 1, nextNote >= notes { break }
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        }
    }
}

private struct BalancePill: View {
    var label: LocalizedStringResource
    var value: Double
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text(verbatim: value.percent())
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: .capsule)
    }
}
