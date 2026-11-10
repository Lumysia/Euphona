import Charts
import EuphonaKit
import SwiftData
import SwiftUI

/// Progress: trends over a chosen range, the activity calendar and every record.
struct ProgressTabView: View {
    @Query(sort: \AnalysisRecord.date) private var records: [AnalysisRecord]
    @Query private var sessions: [PitchSession]
    @Query private var resets: [AverageF0Reset]
    @AppStorage(InsightRange.storageKey) private var range: InsightRange = .month

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker(selection: $range) {
                        ForEach(InsightRange.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: { Text(.dashboardTimeRange) }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if inRange.isEmpty {
                        ContentUnavailableView { Label { Text(.dashboardNoAnalysis) } icon: { Image(systemName: "chart.xyaxis.line") } }
                            .padding(.vertical, 40)
                    } else {
                        MetricCard(metric: .composite, samples: dailyBest, baseline: nil, large: true)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                            ForEach([InsightMetric.pitch, .timbre, .flow, .ease, .variation], id: \.self) { metric in
                                MetricCard(metric: metric, samples: dailyBest, baseline: metric == .pitch ? averageF0 : nil,
                                           large: false)
                            }
                        }
                    }
                    links
                }
                .animation(.smooth(duration: 0.4), value: range)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(Text(.tabProgress))
            .appRoutes()
            .toolbar { RootToolbar() }
        }
    }

    private var inRange: [AnalysisSample] {
        records.map(AnalysisSample.init).filter { range.contains($0.date, now: .now, calendar: .current) }
    }

    private var dailyBest: [AnalysisSample] { range.dailyBest(of: records) }

    private var averageF0: Double? {
        let inRangeSessions = sessions.filter { range.contains($0.date, now: .now, calendar: .current) }.map { ($0.date, $0.meanF0Hz) }
        return Insights.averageF0(analyses: inRange, sessions: inRangeSessions, after: resets.map(\.date).max())
    }

    private var links: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.activity) {
                linkRow(.dashboardActivityTitle, symbol: "calendar", detail: Text(.dashboardAssessmentCount(inRange.count)))
            }
            Divider().padding(.leading, 52)
            NavigationLink(value: Route.history) {
                linkRow(.dashboardAnalysisHistory, symbol: "list.bullet.rectangle", detail: nil)
            }
        }
        .buttonStyle(.card)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
    }

    private func linkRow(_ title: LocalizedStringResource, symbol: String, detail: Text?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 26)
            Text(title).font(.body.weight(.medium))
            Spacer()
            detail?.font(.subheadline).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(.rect)
        .hoverCard(cornerRadius: 22)
    }
}

extension InsightRange {
    var title: LocalizedStringResource {
        switch self {
        case .week: .dashboardRange7Days
        case .month: .dashboardRange30Days
        case .quarter: .dashboardRange90Days
        case .all: .dashboardRangeAll
        }
    }
}

extension InsightMetric {
    var title: LocalizedStringResource {
        switch self {
        case .composite: .dashboardMetricComposite
        case .flow: .dashboardMetricFlow
        case .ease: .dashboardMetricEase
        case .pitch: .dashboardMetricF0
        case .timbre: .dashboardMetricStandard
        case .variation: .dashboardMetricVariation
        }
    }

    var about: LocalizedStringResource {
        switch self {
        case .composite: .dashboardMetricCompositeDescription
        case .flow: .dashboardMetricFlowDescription
        case .ease: .dashboardMetricEaseDescription
        case .pitch: .dashboardMetricPitchDescription
        case .timbre: .dashboardMetricTimbreDescription
        case .variation: .dashboardMetricVariationDescription
        }
    }

    /// The overall score takes the theme color; the components their own, fitted to the theme.
    func color(_ theme: ThemeColors) -> Color {
        switch self {
        case .composite: theme.tint
        case .flow: theme.flow
        case .ease: theme.ease
        case .pitch: theme.deepPink
        case .timbre: theme.timbre
        case .variation: theme.variation
        }
    }

    func format(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return isHertz ? value.hertz(decimals: 1) : value.formatted(decimals: 0)
    }

    func domain(_ values: [Double]) -> ClosedRange<Double> { isHertz ? Insights.hertzRange(values) : 0...100 }
}
