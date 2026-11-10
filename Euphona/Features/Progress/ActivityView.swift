import EuphonaKit
import SwiftData
import SwiftUI

/// A month calendar: days with an analysis glow with that day's best orb color, days the app was
/// opened get a soft dot. Selecting a day lists its analyses.
struct ActivityView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \AnalysisRecord.date, order: .reverse) private var records: [AnalysisRecord]
    @Query private var openedDays: [OpenedDay]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var forward = true

    private let calendar = Calendar.current

    var body: some View {
        List {
            Section {
                header
                grid
                    .id(month)
                    .transition(reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading))
                HStack(spacing: 16) {
                    legend(.dashboardRecordedLegend, style: AnyShapeStyle(.linearGradient(colors: [theme.pink, theme.blue], startPoint: .top, endPoint: .bottom)))
                    legend(.dashboardOpenedLegend, style: AnyShapeStyle(.tint.opacity(0.35)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                let dayRecords = records.filter { calendar.isDate($0.date, inSameDayAs: selected) }
                if dayRecords.isEmpty {
                    Text(.dashboardNoRecordings).foregroundStyle(.secondary)
                }
                ForEach(dayRecords) { record in
                    NavigationLink(value: Route.record(record.persistentModelID)) { RecordRow(record: record) }
                        .recordActions(record)
                }
            } header: {
                Text(selected, format: .dateTime.month(.wide).day().weekday(.wide))
            }
        }
        .navigationTitle(Text(.dashboardActivityTitle))
    }

    private var earliest: Date {
        let first = [records.last?.date, openedDays.map(\.day).min()].compactMap { $0 }.min() ?? .now
        return calendar.dateInterval(of: .month, for: first)!.start
    }

    private var header: some View {
        HStack {
            Text(month, format: .dateTime.year().month(.wide)).font(.title3.bold())
            Spacer()
            Button { shift(-1) } label: { Label { Text(.dashboardPreviousMonth) } icon: { Image(systemName: "chevron.left") } }
                .disabled(month <= earliest)
                .help(Text(.dashboardPreviousMonth))
            Button { shift(1) } label: { Label { Text(.dashboardNextMonth) } icon: { Image(systemName: "chevron.right") } }
                .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
                .help(Text(.dashboardNextMonth))
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .font(.headline)
    }

    private var grid: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let weekdays = Array(symbols[first...] + symbols[..<first])
        let opened = Set(openedDays.map { calendar.startOfDay(for: $0.day) })
        let best = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }.mapValues { $0.max { $0.finalScore < $1.finalScore }! }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { Text($0.element).font(.caption2.bold()).foregroundStyle(.secondary) }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(day: day, best: best[day], opened: opened.contains(day), selected: day == selected,
                            future: day > .now) { selected = day }
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    /// The month's days, padded with `nil` to start on the locale's first weekday.
    private var days: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: month)!
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func shift(_ months: Int) {
        forward = months > 0
        withAnimation(.snappy) { month = calendar.date(byAdding: .month, value: months, to: month)! }
    }

    /// Analysed days show their orb, so the legend's dot is the orb's pink and blue.
    private func legend(_ title: LocalizedStringResource, style: AnyShapeStyle) -> some View {
        Label { Text(title) } icon: { Circle().fill(style).frame(width: 8, height: 8) }
    }
}

private struct DayCell: View {
    var day: Date
    var best: AnalysisRecord?
    var opened: Bool
    var selected: Bool
    var future: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            ZStack {
                if let best {
                    VoiceOrb(balance: best.voiceBalance, halo: false)
                        .padding(3)
                } else if opened {
                    Circle().fill(.tint.opacity(0.16)).padding(3)
                }
                if selected { Circle().strokeBorder(.tint, lineWidth: 2) }
                Text(day, format: .dateTime.day())
                    .font(.callout.weight(best != nil ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(best != nil ? .white : future ? .secondary : .primary)
            }
            .frame(height: 40)
        }
        .buttonStyle(.card)
        .disabled(future)
    }
}
