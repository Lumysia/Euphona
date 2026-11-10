import Charts
import EuphonaKit
import SwiftUI

/// The pages an export draws: one analysis on a page, or the list of analyses as a table. Laid out
/// for an A4 page in light mode with fixed type sizes, so a file looks the same from every device.
enum ReportLayout {
    /// A4 in points.
    static let page = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 40
    /// Table rows that fit under a page's header and above its footer.
    static let rowsPerPage = 24
    /// Pitch curve points drawn at most; the trace is far denser than a page can show.
    static let tracePoints = 600
}

/// One analysis as an export reads it.
struct ReportAnalysis: Identifiable {
    var id: Date { date }
    var date: Date
    var seconds: Double
    var profile: ScoreProfile
    var score: Double
    /// Goal-aligned, 0...100.
    var timbre: Double
    var flow: Double
    var ease: Double
    var pitchHz: Double?
    var breakdown: ScoreBreakdown?
    var trace: [PitchTrace.Point]

    /// `detailed` adds the advice and the pitch curve, which decode the stored result.
    init(_ record: AnalysisRecord, detailed: Bool) {
        date = record.date
        seconds = record.inputSeconds
        profile = record.scoreProfile
        score = record.finalScore
        timbre = record.scoreProfile == .feminization ? record.timbreScore : 100 - record.timbreScore
        flow = record.flowScore
        ease = record.easeScore
        pitchHz = record.speakingF0Hz
        let result = detailed ? record.result : nil
        breakdown = result?.composite
        let points = result.map { PitchTrace(result: $0).points } ?? []
        let step = max(1, points.count / ReportLayout.tracePoints)
        trace = stride(from: 0, to: points.count, by: step).map { points[$0] }
    }

    var goal: VoiceGoal { profile == .feminization ? .feminine : .masculine }
    var pitchProgress: Double? { pitchHz.map { Scoring.pitchProgress($0, goal: profile) } }
}

/// A page's frame: title and details, the content, and a footer with the page number.
struct ReportPage<Content: View>: View {
    var title: LocalizedStringResource
    var details: String
    /// (page, pages) for a PDF page; nil for an image.
    var number: (Int, Int)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 24, weight: .bold))
                    Text(verbatim: details).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: "Euphona").font(.system(size: 14, weight: .semibold)).foregroundStyle(.tint)
            }
            content
            Spacer(minLength: 0)
            HStack {
                Text(.reportFooter)
                Spacer()
                if let number { Text(.reportPage(number.0, number.1)) }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .padding(ReportLayout.margin)
    }
}

/// One analysis: the score, its parts, what to work on, and the pitch curve.
struct AnalysisReport: View {
    var analysis: ReportAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(verbatim: analysis.score.formatted(decimals: 1))
                    .font(.system(size: 56, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Tokens.scoreColor(analysis.score))
                Text(.scoreFinalScore).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            }
            VStack(spacing: 14) {
                ReportBar(title: .timbreTitle, value: analysis.timbre.formatted(decimals: 1), progress: analysis.timbre)
                ReportBar(title: .dashboardMetricF0, value: analysis.pitchHz.map { $0.hertz() } ?? "--", progress: analysis.pitchProgress ?? 0)
                ReportBar(title: .dashboardMetricFlow, value: analysis.flow.formatted(decimals: 1), progress: analysis.flow)
                ReportBar(title: .dashboardMetricEase, value: analysis.ease.formatted(decimals: 1), progress: analysis.ease)
            }
            if let breakdown = analysis.breakdown {
                VStack(alignment: .leading, spacing: 4) {
                    Text(breakdown.focusTitle).font(.system(size: 13, weight: .semibold))
                    Text(breakdown.focusGuidance).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.08), in: .rect(cornerRadius: 12))
            }
            if analysis.trace.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(.analysisExportChartF0).font(.system(size: 13, weight: .semibold))
                    PitchCurve(trace: analysis.trace, goal: analysis.goal).frame(height: 200)
                }
            }
        }
    }
}

/// A component's value with a bar in its score color.
private struct ReportBar: View {
    var title: LocalizedStringResource
    var value: String
    var progress: Double

    var body: some View {
        let color = Tokens.scoreColor(progress)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(verbatim: value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            GeometryReader { proxy in
                Capsule().fill(color.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: proxy.size.width * min(max(progress, 0), 100) / 100)
                    }
            }
            .frame(height: 6)
        }
    }
}

/// The recording's pitch over time, over the goal's typical speaking range.
private struct PitchCurve: View {
    var trace: [PitchTrace.Point]
    var goal: VoiceGoal

    var body: some View {
        let typical = PitchTarget.typicalBand(for: goal).range(at: 0)
        Chart {
            RectangleMark(yStart: .value("Hz", typical.lowerBound), yEnd: .value("Hz", typical.upperBound))
                .foregroundStyle(.tint.opacity(0.1))
            ForEach(Array(trace.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("s", point.time), y: .value("Hz", point.hz), series: .value("run", point.run))
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let seconds = value.as(Double.self) { Text(verbatim: seconds.clock) } }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let hz = value.as(Double.self) { Text(verbatim: hz.hertz(decimals: 0)) } }
            }
        }
        .font(.system(size: 9))
    }
}

/// Analyses as a table, newest first.
struct HistoryTable: View {
    var analyses: [ReportAnalysis]
    /// Each number column; the date takes the rest of the line.
    static let numberWidth: CGFloat = 58

    var body: some View {
        VStack(spacing: 0) {
            row(date: Text(.reportColumnDate), [Text(.reportColumnLength), Text(.scoreFinalScore), Text(.timbreTitle),
                                                 Text(.dashboardMetricF0), Text(.dashboardMetricFlow), Text(.dashboardMetricEase)])
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .overlay(alignment: .bottom) { Divider() }
            ForEach(Array(analyses.enumerated()), id: \.offset) { index, analysis in
                row(date: Text(analysis.date, format: .dateTime.year().month().day().hour().minute()), [
                    Text(verbatim: analysis.seconds.rounded().clock),
                    Text(verbatim: analysis.score.formatted(decimals: 1)).fontWeight(.semibold).foregroundStyle(Tokens.scoreColor(analysis.score)),
                    Text(verbatim: analysis.timbre.formatted(decimals: 1)),
                    Text(verbatim: analysis.pitchHz.map { $0.hertz(decimals: 0) } ?? "--"),
                    Text(verbatim: analysis.flow.formatted(decimals: 1)),
                    Text(verbatim: analysis.ease.formatted(decimals: 1)),
                ])
                .font(.system(size: 10.5))
                .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
            }
        }
        .monospacedDigit()
    }

    private func row(date: Text, _ numbers: [Text]) -> some View {
        HStack(spacing: 0) {
            date.frame(maxWidth: .infinity, alignment: .leading)
            ForEach(numbers.indices, id: \.self) { numbers[$0].frame(width: Self.numberWidth, alignment: .trailing) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
    }
}
