import EuphonaKit
import StoreKit
import SwiftUI

/// What a finished analysis shows: the streak, when this analysis extended it, then the reveal (the
/// orb, the score climbing to its chime, three numbers), then "Full results" moves on to the complete
/// result in place. Each step leads forward only; closing the analysis returns to where it started.
struct ResultReveal: View {
    var content: ResultContent
    @State private var streak: Streak?
    @State private var showsFull = false
    @Environment(\.requestReview) private var requestReview
    /// The app version the review prompt last appeared in.
    @AppStorage("review_prompt_version") private var reviewPromptVersion = ""

    /// `streak` is shown first when non-nil.
    init(content: ResultContent, streak: Streak?) {
        self.content = content
        _streak = State(initialValue: streak)
    }

    var body: some View {
        Group {
            if showsFull {
                ResultView(content: content, animate: false)
                    .navigationTitle(Text(.analysisResultTitle))
                    .transition(.push(from: .trailing))
            } else if let streak {
                StreakCelebration(streak: streak) { withAnimation(.smooth(duration: 0.5)) { self.streak = nil } }
                    .transition(.blurReplace)
            } else {
                reveal.transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.45), value: showsFull)
    }

    private var reveal: some View {
        let breakdown = content.result.composite
        return ScrollView {
            VStack(spacing: 28) {
                ScoreHero(score: breakdown.finalScore, previousScore: content.previousScore,
                          balance: content.result.voiceBalance, animate: true)
                HStack(spacing: 0) {
                    number(.timbreTitle, breakdown.timbre.formatted(decimals: 0))
                    Divider().frame(height: 36)
                    number(.pitchTitle, content.result.f0.speakingHz.map { $0.hertz() } ?? "--")
                    Divider().frame(height: 36)
                    number(.scoreComponentFlow, breakdown.flow.formatted(decimals: 0))
                    Divider().frame(height: 36)
                    number(.scoreComponentEase, breakdown.ease.formatted(decimals: 0))
                }
                .padding(.vertical, 14)
                .background(Color.groupedCell.opacity(0.7), in: .rect(cornerRadius: 22))
                Label { Text(breakdown.focusTitle) } icon: {
                    Image(systemName: breakdown.bottleneck == nil ? "checkmark.seal.fill" : "arrow.up.forward.circle.fill")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { AmbientBackground(balance: content.result.voiceBalance) }
        .safeAreaBar(edge: .bottom) {
            Button { askForReviewIfDeserved(); showsFull = true } label: {
                HStack(spacing: 6) {
                    Text(.revealFullResults)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
                }
                .font(.headline)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 12)
        }
    }

    /// A clear improvement is a good moment to ask for a review, at most once per version (the system
    /// limits it further).
    private func askForReviewIfDeserved() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard let previous = content.previousScore, content.result.composite.finalScore >= previous + Self.reviewImprovement,
              reviewPromptVersion != version else { return }
        reviewPromptVersion = version
        requestReview()
    }

    static let reviewImprovement = 3.0

    private func number(_ title: LocalizedStringResource, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: value).font(.title3.weight(.semibold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The streak, celebrated: the flame, the day count rolling up, and the week filling in today.
struct StreakCelebration: View {
    var streak: Streak
    var done: () -> Void
    @State private var counted = false
    @State private var chime = ResultChime()
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var days: Int { counted ? streak.days : max(streak.days - 1, 0) }

    /// "5-day streak" in the language's own plural, with the number drawn large wherever the
    /// sentence puts it, so the words always agree with the count.
    private var streakLine: AttributedString {
        var line = AttributedString(localized: .todayStreak(days))
        line.font = .title3.weight(.semibold)
        line.foregroundColor = .secondary
        let number = [days.formatted(), "\(days)"].lazy.compactMap { line.range(of: $0) }.first
        if let number {
            line[number].font = .system(size: 76, weight: .heavy, design: .rounded)
            line[number].foregroundColor = .primary
        }
        return line
    }


    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            Image(systemName: "flame.fill")
                .scaledFont(size: 112, weight: .bold)
                .foregroundStyle(.linearGradient(colors: [Color(hex: 0xFFC145).mix(with: theme.tint, by: ThemeColors.harmony), theme.deepPink],
                                                 startPoint: .top, endPoint: .bottom))
                .symbolEffect(.bounce, value: counted)
                .shadow(color: theme.deepPink.opacity(0.35), radius: 24, y: 8)
            Text(streakLine)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText(value: Double(days)))
            WeekRow(week: streak.week, todayFilled: counted)
            Text(streak.days <= 1 ? LocalizedStringResource.streakStarted : .streakKeepGoing)
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background { AmbientBackground(balance: 0.5) }
        .safeAreaBar(edge: .bottom) {
            Button(action: done) {
                Text(.coachContinue).font(.headline).padding(.horizontal, 24).frame(minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.success, trigger: counted)
        .task {
            do { try await Task.sleep(for: .seconds(0.5)) } catch { return }
            withAnimation(reduceMotion ? .default : .spring(response: 0.5, dampingFraction: 0.55)) { counted = true }
            // Two rising notes for the new day.
            chime.play(step: 7, loudness: 0.6)
            do { try await Task.sleep(for: .seconds(0.14)) } catch { return }
            chime.land(step: 10)
        }
        .onDisappear { chime.stop() }
        .accessibilityElement(children: .contain)
    }
}

/// The last seven days, today last; today's dot fills when the count rolls up.
private struct WeekRow: View {
    var week: [Bool]
    var todayFilled: Bool

    private var weekdays: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let today = calendar.component(.weekday, from: .now)
        return (0..<7).reversed().map { symbols[((today - 1 - $0) % 7 + 7) % 7] }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(zip(week.indices, weekdays)), id: \.0) { index, symbol in
                let active = index == week.count - 1 ? todayFilled : week[index]
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        if active {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 32, height: 32)
                    Text(verbatim: symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
