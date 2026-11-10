import Charts
import EuphonaKit
import SwiftData
import SwiftUI

/// Home: the latest result as the orb, the streak, the trend, and recent analyses.
struct TodayView: View {
    @Environment(\.startAnalysis) private var startAnalysis
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]
    @Query private var sessions: [PitchSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let latest = records.first {
                        LatestHero(record: latest)
                        streakAndTrend
                        RecentSection(records: Array(records.prefix(3)))
                    } else {
                        FirstRunHero(action: startAnalysis)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background { AmbientBackground(balance: records.first?.voiceBalance ?? 0.5) }
            .navigationTitle(Text(.tabToday))
            .appRoutes()
            .toolbar { RootToolbar() }
        }
    }

    /// Days in a row with an analysis or a pitch session.
    private var streak: Int {
        let calendar = Calendar.current
        let days = records.map(\.date) + sessions.map(\.date)
        return Insights.streak(days: Set(days.map { calendar.startOfDay(for: $0) }), now: .now, calendar: calendar)
    }

    @ViewBuilder private var streakAndTrend: some View {
        if streak >= 1 {
            StreakBadge(days: streak)
        }
        let best = Insights.dailyBest(records.map(AnalysisSample.init), calendar: .current).suffix(30)
        if best.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text(.dashboardMetricChart).font(.headline)
                TrendChart(points: best.map { ($0.date, $0.finalScore) }, metric: .composite, interactive: true, since: nil)
                    .frame(height: 150)
            }
            .padding(20)
            .background(.background.secondary, in: .rect(cornerRadius: 26))
        }
    }
}

/// The newest analysis as the orb with its score; tapping it starts a new analysis (the recent list
/// opens past records).
private struct LatestHero: View {
    var record: AnalysisRecord
    @Environment(\.orbScale) private var orbScale
    @Environment(\.startAnalysis) private var startAnalysis

    var body: some View {
        Button(action: startAnalysis) {
            VStack(spacing: 14) {
                VoiceOrb(balance: record.voiceBalance, halo: false).frame(width: 190 * orbScale, height: 190 * orbScale)
                    .glassBubble(diameter: 190 * orbScale, balance: record.voiceBalance)
                    .padding(.top, 8)
                Text(.todayLatestAnalysis).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(verbatim: record.finalScore.formatted(decimals: 1))
                    .scaledFont(size: 56, weight: .heavy, design: .rounded).monospacedDigit()
                Text(record.date, format: .relative(presentation: .named))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.primary)
            .hoverCard(cornerRadius: 32)
        }
        .buttonStyle(.card)
        .accessibilityHint(Text(.actionAnalyzeVoice))
    }
}

private struct FirstRunHero: View {
    var action: () -> Void
    @Environment(\.orbScale) private var orbScale

    var body: some View {
        VStack(spacing: 22) {
            VoiceOrb(balance: 0.5, halo: false).frame(width: 220 * orbScale, height: 220 * orbScale)
                .glassBubble(diameter: 220 * orbScale, balance: 0.5)
                .padding(.top, 24)
            VStack(spacing: 8) {
                Text(.todayFirstTitle).font(.title.bold())
                Text(.todayFirstBody).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button(action: action) {
                Label { Text(.actionAnalyzeVoice) } icon: { Image(systemName: "mic.fill") }
                    .font(.headline).padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 12)
    }
}

/// A short list of the latest analyses.
struct RecentSection: View {
    var records: [AnalysisRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.todayRecent).font(.title3.bold())
            VStack(spacing: 0) {
                ForEach(records) { record in
                    NavigationLink(value: Route.record(record.persistentModelID)) {
                        RecordRow(record: record, showsChevron: true).hoverCard(cornerRadius: 16)
                    }
                    .buttonStyle(.card)
                    .recordActions(record, swipes: false)
                    .accessibilityIdentifier("today.recent")
                    if record.id != records.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 22))
        }
    }
}

/// The practice streak: pops in, the flame flickers every few seconds, and the count rolls when it grows.
private struct StreakBadge: View {
    var days: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(.linearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                .symbolEffect(.bounce.up, options: .repeat(.periodic(delay: 2.5)), isActive: shown && !reduceMotion)
            Text(.todayStreak(days))
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText(value: Double(days)))
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.orange.opacity(0.12), in: .capsule)
        .scaleEffect(shown || reduceMotion ? 1 : 0.4)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.2)) { shown = true } }
        .animation(.snappy, value: days)
        .sensoryFeedback(.increase, trigger: days)
    }
}
