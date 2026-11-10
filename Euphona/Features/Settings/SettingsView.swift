import EuphonaKit
import SwiftData
import SwiftUI

/// Settings: a list with pushed pages on iPhone and iPad, the standard tabbed Settings window on Mac.
struct SettingsView: View {
    @Environment(ErrorCenter.self) private var errors
    enum Page: String { case general, advanced, about }

    @Environment(\.dismiss) private var dismiss
    @State private var page = Self.initialPage

    /// Debug builds accept `-demo_settings_tab <page>` so screenshots can open any page.
    private static var initialPage: Page {
        #if DEBUG
        UserDefaults.standard.string(forKey: "demo_settings_tab").flatMap(Page.init) ?? .general
        #else
        .general
        #endif
    }

    var body: some View {
        #if os(macOS)
        TabView(selection: $page) {
            // Each page sizes the window to its content, the way Mac Settings windows resize between tabs.
            Tab(value: .general) { GeneralSettings().frame(height: 380) } label: { Label { Text(.settingsGeneral) } icon: { Image(systemName: "gearshape") } }
            Tab(value: .advanced) { AdvancedSettings().frame(height: 620) } label: { Label { Text(.settingsAdvanced) } icon: { Image(systemName: "slider.horizontal.3") } }
            Tab(value: .about) { AboutView().frame(height: 560) } label: { Label { Text(.settingsAbout) } icon: { Image(systemName: "info.circle") } }
        }
        .errorAlerts(errors)
        #else
        NavigationStack {
            GeneralSettings()
                .navigationTitle(Text(.settingsTitle))
                .appRoutes()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(role: .close) { dismiss() } }
                }
        }
        .errorAlerts(errors)
        #endif
    }
}

/// Voice goal, theme and erasing; on iPhone and iPad also the links to the other pages.
private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ErrorCenter.self) private var errors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var confirmingErase = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            #if os(macOS)
            // Mac forms put the label on the left and stack the radio buttons on the right.
            Section {
                Picker(selection: $settings.voiceGoal) {
                    ForEach(VoiceGoal.allCases, id: \.self) { goal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title)
                            Text(goal.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(goal)
                    }
                } label: { Text(.settingsVoiceGoal) }
                .pickerStyle(.radioGroup)
                LabeledContent { ThemePicker(selection: $settings.palette).frame(maxWidth: 300) } label: { Text(.settingsTheme) }
            }
            #else
            Section {
                Picker(selection: $settings.voiceGoal) {
                    ForEach(VoiceGoal.allCases, id: \.self) { goal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title)
                            Text(goal.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(goal)
                    }
                } label: { Text(.settingsVoiceGoal) }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text(.settingsVoiceGoal) }

            Section {
                ThemePicker(selection: $settings.palette)
            } header: { Text(.settingsTheme) }
            #endif

            Section {
                Toggle(isOn: $settings.syncsWithICloud) { Text(.settingsIcloudSync) }
            } footer: { Text(.settingsIcloudSyncFooter) }

            CoachModelSection()

            #if os(iOS)
            Section {
                NavigationLink(value: Route.advancedSettings) {
                    VStack(alignment: .leading) {
                        Text(.settingsAdvanced)
                        Text(.settingsAdvancedDesc).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
                    LabeledContent { Image(systemName: "arrow.up.forward.app") } label: { Text(.settingsLanguage) }
                }
            }

            Section {
                NavigationLink(value: Route.about) { Text(.settingsAbout) }
                NavigationLink(value: Route.feedback) { Text(.feedbackTitle) }
            }
            #endif

            Section {
                eraseButton
            }
        }
        .formStyle(.grouped)
        .sensoryFeedback(.selection, trigger: settings.voiceGoal)
    }

    /// A destructive row on iPhone and iPad; a right-aligned push button on Mac.
    @ViewBuilder private var eraseButton: some View {
        let button = Button(role: .destructive) { confirmingErase = true } label: { Text(.settingsEraseAll) }
            .confirmationDialog(Text(.settingsEraseAll), isPresented: $confirmingErase) {
                Button(role: .destructive) { eraseEverything() } label: { Text(.settingsEraseAll) }
            } message: {
                Text(.settingsEraseAllMessage)
            }
        #if os(macOS)
        HStack {
            Spacer()
            button
        }
        #else
        button
        #endif
    }

    /// Deletes all history (here and in iCloud) and every setting; the app returns to onboarding.
    private func eraseEverything() {
        errors.attempt(.errorEraseFailed) { try HistoryStore(context: modelContext).deleteEverything() }
        settings.reset()
        dismiss()
    }
}

private struct ThemePicker: View {
    @Binding var selection: ThemePaletteID

    var body: some View {
        HStack {
            ForEach(ThemePaletteID.allCases, id: \.self) { palette in
                Button { withAnimation(.snappy) { selection = palette } } label: {
                    Circle().fill(palette.tint)
                        .frame(width: 34, height: 34)
                        .overlay { if selection == palette { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                        .padding(3)
                        .overlay { Circle().strokeBorder(selection == palette ? palette.tint : .clear, lineWidth: 2) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(palette.title))
                .accessibilityAddTraits(selection == palette ? .isSelected : [])
                if palette != ThemePaletteID.allCases.last { Spacer(minLength: 0) }
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct AdvancedSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker(selection: $settings.pitchChartStyle) {
                    Text(.settingsF0ChartCurve).tag(PitchChartStyle.curve)
                    Text(.settingsF0ChartDots).tag(PitchChartStyle.dots)
                } label: { Text(.analysisExportChartF0) }
                .pickerStyle(.segmented)
                slider(.settingsF0Min, value: $settings.analyzer.minF0Hz, in: AnalyzerSettings.f0Range, step: 5) { Text(.settingsF0Hz(Int($0))) }
                slider(.settingsF0Max, value: $settings.analyzer.maxF0Hz, in: AnalyzerSettings.f0Range, step: 5) { Text(.settingsF0Hz(Int($0))) }
                slider(.settingsF0Confidence, value: $settings.analyzer.minConfidence, in: AnalyzerSettings.confidenceRange, step: 0.01) {
                    Text(.settingsF0Ratio($0))
                }
                // Right means a shorter silence breaks the trace.
                slider(.settingsF0Gap, value: Binding(
                    get: { Float(AppSettings.gapRange.upperBound + AppSettings.gapRange.lowerBound - settings.gapThresholdMs) },
                    set: { settings.gapThresholdMs = AppSettings.gapRange.upperBound + AppSettings.gapRange.lowerBound - Int($0) }
                ), in: Float(AppSettings.gapRange.lowerBound)...Float(AppSettings.gapRange.upperBound), step: 10) { _ in
                    Text(.settingsF0Ms(settings.gapThresholdMs))
                }
            } header: { Text(.settingsF0Title) }

            Section {
                slider(.settingsF0SampleRate, value: Binding(get: { Float(settings.f0SampleRate) }, set: { settings.f0SampleRate = Int($0) }),
                       in: Float(AppSettings.f0SampleRateRange.lowerBound)...Float(AppSettings.f0SampleRateRange.upperBound), step: 1) {
                    Text(.settingsF0RateValue(Int($0)))
                }
                slider(.settingsThreads, value: Binding(get: { Float(settings.analyzer.threads) }, set: { settings.analyzer.threads = Int($0) }),
                       in: 1...Float(AnalyzerSettings.maximumThreads), step: 1) { Text(verbatim: "\(Int($0))") }
            } header: { Text(.settingsPerformanceTitle) }

            #if os(macOS)
            Section {} footer: {
                HStack {
                    Spacer()
                    Button(action: reset) { Text(.settingsF0Reset) }
                }
            }
            #else
            Section {
                Button(role: .destructive, action: reset) { Text(.settingsF0Reset) }
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle(Text(.settingsAdvanced))
    }

    private func reset() {
        settings.resetAnalyzer()
        settings.gapThresholdMs = AppSettings.defaultGapMs
        settings.f0SampleRate = AppSettings.defaultF0SampleRate
    }

    private func slider(_ title: LocalizedStringResource, value: Binding<Float>, in range: ClosedRange<Float>, step: Float,
                        label: @escaping (Float) -> Text) -> some View {
        // No `step:` on the slider itself: it would draw a tick mark per step. The binding snaps instead.
        let snapped = Binding<Float>(get: { value.wrappedValue }, set: { value.wrappedValue = ($0 / step).rounded() * step })
        return VStack(alignment: .leading) {
            LabeledContent { label(value.wrappedValue).monospacedDigit() } label: { Text(title) }
            Slider(value: snapped, in: range)
        }
    }
}
