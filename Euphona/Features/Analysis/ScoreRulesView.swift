import EuphonaKit
import SwiftUI

/// How the overall score came about: the three components, the one formula with this recording's
/// numbers in it, and what costs the most points.
struct ScoreRulesView: View {
    var result: EuphonaResult
    var previousScore: Double?
    var previous: PreviousMetrics?

    private var breakdown: ScoreBreakdown { result.composite }
    private var masculine: Bool { result.scoreProfile == .masculinization }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(.scoreFinalScore).font(.subheadline).foregroundStyle(.secondary)
                        Text(verbatim: breakdown.finalScore.formatted(decimals: 1))
                            .scaledFont(size: 52, weight: .heavy, design: .rounded).monospacedDigit()
                    }
                    Spacer()
                    delta
                }
                .padding(.vertical, 6)
            }
            Section {
                ComponentRow(title: ScoreMetric.timbre.title, value: breakdown.timbre.formatted(decimals: 0), progress: breakdown.timbre,
                             note: Text(.scoreComponentWeight((breakdown.pitch == nil ? 1 : Scoring.timbreWeight).formatted(decimals: 1))),
                             gain: gain(.timbre), change: previousTimbre.map { breakdown.timbre - $0 }, format: .score)
                if let pitch = breakdown.pitch, let hz = result.f0.speakingHz {
                    ComponentRow(title: ScoreMetric.f0.title, value: hz.hertz(), progress: pitch,
                                 note: Text(.scoreComponentPitchProgress(pitch.formatted(decimals: 0), Scoring.pitchWeight.formatted(decimals: 1))),
                                 gain: gain(.f0), change: previous?.speakingF0Hz.map { hz - $0 }, format: .hertz)
                } else {
                    LabeledContent { Text(.scoreValueNotDetected) } label: { Text(ScoreMetric.f0.title) }
                }
                ComponentRow(title: ScoreMetric.flow.title, value: breakdown.flow.formatted(decimals: 0), progress: breakdown.flow,
                             note: Text(.scoreComponentFlowMeasures(result.flow.articulationRate.formatted(decimals: 1),
                                                                    (100 * result.flow.pauseShare).percent(decimals: 0))),
                             gain: gain(.flow), change: previous.map { breakdown.flow - $0.flowScore }, format: .score)
                ComponentRow(title: ScoreMetric.ease.title, value: breakdown.ease.formatted(decimals: 0), progress: breakdown.ease,
                             note: Text(.scoreComponentFluency(breakdown.fluency.formatted(decimals: 2))),
                             gain: gain(.ease), change: previous.map { breakdown.ease - $0.easeScore }, format: .score)
            } header: { Text(.scoreComponentsTitle) } footer: { Text(masculine ? LocalizedStringResource.scoreComponentsFooterMasculine : .scoreComponentsFooter) }
            Section {
                FormulaBlock(lines: Self.formula(masculine: masculine))
                FormulaBlock(lines: worked)
            } header: { Text(.scoreFormulaTitle) } footer: { Text(.scoreFormulaFooter) }
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(breakdown.focusTitle).font(.headline)
                        Text(breakdown.focusGuidance).font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: breakdown.bottleneck == nil ? "checkmark.seal.fill" : "arrow.up.forward.circle.fill")
                        .foregroundStyle(breakdown.bottleneck == nil ? Tokens.success : Color.accentColor)
                        .font(.title2)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(.scoreRulesTitle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var previousTimbre: Double? { previous.map { masculine ? 100 - $0.timbreScore : $0.timbreScore } }

    /// Points working on a component could still add.
    private func gain(_ metric: ScoreMetric) -> Double {
        breakdown.losses.first { $0.metric == metric }?.points ?? 0
    }

    @ViewBuilder private var delta: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(.scoreComparePrevious).font(.caption).foregroundStyle(.secondary)
            if let previousScore {
                let change = breakdown.finalScore - previousScore
                Text(verbatim: change.change())
                    .font(.title3.bold())
                    .foregroundStyle(change > 0.05 ? Tokens.success : change < -0.05 ? Tokens.danger : .secondary)
            } else {
                Text(.scoreFirstTest).font(.headline).foregroundStyle(.secondary)
            }
        }
    }

    /// The one formula, the same for both goals except which way pitch counts.
    static func formula(masculine: Bool) -> [String] {
        let low = Scoring.masculinePitchHz.formatted(decimals: 0), high = Scoring.femininePitchHz.formatted(decimals: 0)
        let ratio = "log_2(F₀ ⁄ \(low)) ⁄ log_2(\(high) ⁄ \(low))"
        return [
            "Voice = 0.6 × Timbre + 0.4 × Pitch",
            masculine ? "Pitch = 100 − 100 × \(ratio)" : "Pitch = 100 × \(ratio)",
            "Fluency = 0.8 + 0.2 × smooth((min(Flow, Ease) − 30) ⁄ 50)",
            "Final = Voice × Fluency",
        ]
    }

    /// This recording's numbers in the formula.
    private var worked: [String] {
        let b = breakdown
        let voice = b.pitch.map { "Voice = 0.6 × \(b.timbre.formatted(decimals: 1)) + 0.4 × \($0.formatted(decimals: 1)) = \(b.voice.formatted(decimals: 1))" }
            ?? "Voice = Timbre = \(b.voice.formatted(decimals: 1))"
        return [voice, "Final = \(b.voice.formatted(decimals: 1)) × \(b.fluency.formatted(decimals: 2)) = \(b.finalScore.formatted(decimals: 1))"]
    }
}

/// One component: its value with a bar, its share in the formula, what it could still add, and the
/// change since last time.
private struct ComponentRow: View {
    var title: LocalizedStringResource
    var value: String
    var progress: Double
    var note: Text
    var gain: Double
    var change: Double?
    var format: MetricFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.body)
                Spacer()
                if let change, abs(change) > format.threshold {
                    Text(verbatim: format.change(change)).font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(change > 0 ? Tokens.success : .secondary)
                }
                Text(verbatim: value).font(.headline.monospacedDigit())
            }
            ProgressView(value: min(max(progress, 0), 100), total: 100)
                .tint(Tokens.scoreColor(progress))
            HStack {
                note
                Spacer()
                if gain >= 0.5 { Text(.scoreComponentGain(gain.formatted(decimals: 0))) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct FormulaBlock: View {
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                Text(Self.typeset(line))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Capsule().fill(.tint).frame(width: 3) }
        .textSelection(.enabled)
    }

    /// `X_r` and `s_F` become real subscripts: a smaller size on a lowered baseline. Unicode subscript
    /// characters such as ᵣ and ₀ are missing from the italic system font and showed as gaps.
    static func typeset(_ line: String) -> AttributedString {
        let body = Font.system(.callout, design: .serif).italic()
        let small = Font.system(.caption2, design: .serif).italic()
        var result = AttributedString()
        // F₀'s subscript zero is missing from the italic font too; it becomes F_0, a typeset subscript.
        var rest = Substring(line.replacingOccurrences(of: "₀", with: "_0"))
        while let underscore = rest.firstIndex(of: "_") {
            var plain = AttributedString(String(rest[..<underscore]))
            plain.font = body
            result += plain
            let after = rest.index(after: underscore)
            let end = rest[after...].firstIndex { !($0.isLetter || $0.isNumber) } ?? rest.endIndex
            var subscriptRun = AttributedString(String(rest[after..<end]))
            subscriptRun.font = small
            subscriptRun.baselineOffset = -3
            result += subscriptRun
            rest = rest[end...]
        }
        var tail = AttributedString(String(rest))
        tail.font = body
        return result + tail
    }
}
