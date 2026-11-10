import Charts
import EuphonaKit
import SwiftData
import SwiftUI

/// A metric's latest value, its change against the earlier average, and a trend line.
struct MetricCard: View {
    @Environment(\.theme) private var theme
    var metric: InsightMetric
    var samples: [AnalysisSample]
    /// Overrides the mean of earlier values (pitch uses the average F0 of sessions and analyses).
    var baseline: Double?
    var large: Bool
    @AppStorage(InsightRange.storageKey) private var range: InsightRange = .month

    var body: some View {
        let points = samples.compactMap { sample in metric.value(sample).map { (sample.date, $0) } }
        let values = points.map(\.1)
        let summary = Insights.latestAndBaseline(values)
        let reference = baseline ?? summary.baseline
        let latest = metric == .pitch ? samples.last?.speakingF0Hz : summary.latest
        NavigationLink(value: Route.metric(metric)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(metric.title).font(.subheadline.weight(.semibold)).foregroundStyle(metric.color(theme))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: metric.format(latest))
                        .scaledFont(size: large ? 44 : 28, weight: .heavy, design: .rounded, relativeTo: large ? .largeTitle : .title).monospacedDigit()
                        .lineLimit(1)
                    if let change = Insights.percentChange(latest, from: reference) {
                        Text(change > 0 ? .dashboardChangeUp(Float(abs(change))) : .dashboardChangeDown(Float(abs(change))))
                            .font(.caption.bold())
                            .foregroundStyle(change > 0 ? Tokens.success : Tokens.danger)
                            .lineLimit(1)
                    }
                }
                .minimumScaleFactor(0.7)
                if let reference {
                    Text(.dashboardBaselineAverage(metric.format(reference))).font(.caption).foregroundStyle(.secondary)
                }
                // Cards in a grid row share its height; the chart sits at the bottom so the charts line up.
                Spacer(minLength: 0)
                if points.count < 2, let value = points.first?.1 {
                    LevelBar(metric: metric, value: value, showsLabels: large).padding(.top, large ? 8 : 4)
                    if large { TrendHint().padding(.top, 4) }
                } else {
                    TrendChart(points: points, metric: metric, interactive: false, since: range.start(now: .now, calendar: .current))
                        .frame(height: large ? 140 : 64)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
            .background(.background.secondary, in: .rect(cornerRadius: 24))
            .foregroundStyle(.primary)
            .hoverCard(cornerRadius: 24)
        }
        .buttonStyle(.card)
    }
}

extension InsightRange {
    /// Where the chosen range is stored, shared by Progress and every metric's detail.
    static let storageKey = "insight_range"

    /// The best analysis of each day within this range, oldest first.
    func dailyBest(of records: [AnalysisRecord], now: Date = .now, calendar: Calendar = .current) -> [AnalysisSample] {
        let inRange = records.map(AnalysisSample.init).filter { contains($0.date, now: now, calendar: calendar) }
        return Insights.dailyBest(inRange, calendar: calendar)
    }
}

struct TrendChart: View {
    @Environment(\.theme) private var theme
    var points: [(Date, Double)]
    var metric: InsightMetric
    var interactive: Bool
    /// Where the time axis starts, so a single point sits at the right with room for the trend to come.
    var since: Date?
    @State private var selection: Date?

    var body: some View {
        if points.count == 1, let point = points.first {
            single(point)
        } else {
            trend
        }
    }

    /// One analysis so far: where the value sits on its scale, until there is a trend to draw.
    private func single(_ point: (Date, Double)) -> some View {
        LevelBar(metric: metric, value: point.1, showsLabels: interactive)
    }

    private var trend: some View {
        Chart {
            ForEach(points, id: \.0) { date, value in
                AreaMark(x: .value("Date", date), yStart: .value("Base", metric.domain(points.map(\.1)).lowerBound),
                         yEnd: .value("Value", value))
                    .foregroundStyle(.linearGradient(colors: [metric.color(theme).opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", date), y: .value("Value", value))
                    .foregroundStyle(metric.color(theme))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: interactive ? 3 : 2.5, lineCap: .round))
            }
            if interactive, let selection, let point = points.min(by: { abs($0.0.timeIntervalSince(selection)) < abs($1.0.timeIntervalSince(selection)) }) {
                RuleMark(x: .value("Date", point.0)).foregroundStyle(.secondary.opacity(0.4))
                PointMark(x: .value("Date", point.0), y: .value("Value", point.1))
                    .foregroundStyle(metric.color(theme))
                    .annotation(position: .top) {
                        Text(verbatim: metric.format(point.1)).font(.caption.bold().monospacedDigit())
                            .padding(.horizontal, 8).padding(.vertical, 4).background(.regularMaterial, in: .capsule)
                    }
            }
        }
        .chartYScale(domain: metric.domain(points.map(\.1)))
        .chartXAxis(interactive ? .automatic : .hidden)
        .chartYAxis(interactive ? .automatic : .hidden)
        .selectable(interactive, selection: $selection)
    }
}

private extension View {
    /// Interactive charts select a date under the finger. Chart thumbnails sit inside links: any
    /// selection gesture there, even bound to a constant, swallows the tap meant for the link.
    @ViewBuilder func selectable(_ interactive: Bool, selection: Binding<Date?>) -> some View {
        if interactive {
            chartXSelection(value: selection)
        } else {
            allowsHitTesting(false)
        }
    }
}

/// A value on its scale: score bands for scores (with the 60 pass line for the overall score), pink above
/// and blue below 165 Hz for pitch.
struct LevelBar: View {
    @Environment(\.theme) private var theme
    var metric: InsightMetric
    var value: Double
    var showsLabels: Bool

    private var range: ClosedRange<Double> {
        switch metric {
        case .pitch: 80...300
        case .variation: 0...max(60, value * 1.5)
        default: 0...100
        }
    }

    private var marks: [Double] {
        switch metric {
        case .composite: [0, 60, 100]
        case .pitch: [80, Scoring.pitchMidpointHz, 300]
        case .variation: [range.lowerBound, range.upperBound]
        default: [0, 50, 100]
        }
    }

    private var track: LinearGradient {
        switch metric {
        case .pitch:
            let split = (Scoring.pitchMidpointHz - range.lowerBound) / (range.upperBound - range.lowerBound)
            return LinearGradient(stops: [.init(color: theme.masculineFill, location: 0), .init(color: theme.masculineFill, location: split),
                                          .init(color: theme.feminineFill, location: split), .init(color: theme.feminineFill, location: 1)],
                                  startPoint: .leading, endPoint: .trailing)
        case .variation:
            return LinearGradient(colors: [metric.color(theme).opacity(0.3), metric.color(theme)], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [Tokens.scoreLow, Tokens.scoreLowMid, Tokens.scoreMid, Tokens.scoreHighMid, Tokens.scoreHigh],
                                  startPoint: .leading, endPoint: .trailing)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(track.opacity(0.85)).frame(height: 10).offset(y: 14)
                ForEach(marks, id: \.self) { mark in
                    if mark != range.lowerBound && mark != range.upperBound {
                        Capsule().fill(.primary.opacity(0.5)).frame(width: 2, height: 18).offset(x: x(mark, width) - 1, y: 10)
                    }
                    if showsLabels {
                        Text(verbatim: "\(Int(mark))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: min(max(x(mark, width) - 10, 0), width - 24), y: 32)
                    }
                }
                Circle().fill(.background).frame(width: 22, height: 22)
                    .overlay { Circle().strokeBorder(metric.color(theme), lineWidth: 5) }
                    .shadow(color: metric.color(theme).opacity(0.4), radius: 6)
                    .offset(x: x(value, width) - 11, y: 8)
            }
        }
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: metric.format(value)))
        .frame(height: showsLabels ? 48 : 38)
    }

    private func x(_ value: Double, _ width: CGFloat) -> CGFloat {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound)) * width
    }
}

/// Shown under a chart until there are at least two days to compare.
struct TrendHint: View {
    var body: some View {
        Label { Text(.dashboardMetricEmptyDescription) } icon: { Image(systemName: "sparkles") }
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Reads its own data, so it only needs the metric (see `Route`).
struct MetricDetailView: View {
    var metric: InsightMetric
    @Query(sort: \AnalysisRecord.date) private var records: [AnalysisRecord]
    @AppStorage(InsightRange.storageKey) private var range: InsightRange = .month

    var body: some View {
        let samples = range.dailyBest(of: records)
        let points = samples.compactMap { sample in metric.value(sample).map { (sample.date, $0) } }
        let values = points.map(\.1)
        Form {
            Section {
                Picker(selection: $range) {
                    ForEach(InsightRange.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: { Text(.dashboardTimeRange) }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                if points.isEmpty {
                    Text(.dashboardMetricEmptyDescription).foregroundStyle(.secondary)
                } else {
                    if points.count < 2, let value = points.first?.1 {
                        LevelBar(metric: metric, value: value, showsLabels: true).padding(.vertical, 12)
                        TrendHint()
                    } else {
                        TrendChart(points: points, metric: metric, interactive: true, since: range.start(now: .now, calendar: .current))
                            .frame(height: 240).padding(.vertical, 8)
                    }
                }
            }
            Section {
                stat(.dashboardMetricLatest, values.last)
                stat(.dashboardMetricAverage, values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))
                stat(.dashboardMetricMinimum, values.min())
                stat(.dashboardMetricMaximum, values.max())
            }
            Section {
                Text(metric.about)
                Text(.dashboardMetricDailyBestNote).foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .formStyle(.grouped)
        .navigationTitle(Text(metric.title))
    }

    private func stat(_ title: LocalizedStringResource, _ value: Double?) -> some View {
        LabeledContent { Text(verbatim: metric.format(value)).monospacedDigit().fontWeight(.semibold) } label: { Text(title) }
    }
}
