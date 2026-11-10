import EuphonaKit
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case today, practice, progress, coach

    var title: LocalizedStringResource {
        switch self {
        case .today: .tabToday
        case .practice: .tabPractice
        case .progress: .tabProgress
        case .coach: .tabCoach
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .practice: "waveform.path"
        case .progress: "chart.line.uptrend.xyaxis"
        case .coach: "graduationcap"
        }
    }

    var label: some View { Label { Text(title) } icon: { Image(systemName: symbol) } }
}

/// What the menu bar (Mac, and iPad with a keyboard) can do in the focused window.
struct SceneActions {
    var tab: AppTab
    var selectTab: (AppTab) -> Void
    var startAnalysis: () -> Void
}

extension FocusedValues {
    @Entry var sceneActions: SceneActions?
}

extension EnvironmentValues {
    /// Opens the full-screen voice analysis from anywhere.
    @Entry var startAnalysis: () -> Void = {}
    /// Opens Settings from anywhere.
    @Entry var showSettings: () -> Void = {}
    /// Switches to the Coach tab, closing the analysis; nil where the tabs are not reachable.
    @Entry var openCoach: OpenCoachAction?
}

struct OpenCoachAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

struct RootView: View {
    @Environment(ErrorCenter.self) private var errors
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(VoiceEngine.self) private var engine
    @Environment(\.theme) private var theme
    @SceneStorage("tab") private var tab: AppTab = .today
    @State private var analyzing = false
    @State private var showsSettings = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    #endif
    @Namespace private var zoom
    @State private var orbScale: CGFloat = 1
    #if DEBUG
    @State private var demoScreen: DemoScreen?
    #endif

    var body: some View {
        content
            .onGeometryChange(for: CGFloat.self) { OrbScale.forWindow($0.size) } action: { orbScale = $0 }
            .environment(\.orbScale, orbScale)
    }

    /// A sheet on iPhone and iPad; the Settings window on Mac.
    private func showSettings() {
        #if os(macOS)
        openSettings()
        #else
        showsSettings = true
        #endif
    }

    /// Full screen on iPhone and iPad; its own window on Mac.
    private func startAnalysis() {
        #if os(macOS)
        openWindow(id: AnalysisView.windowID)
        #else
        analyzing = true
        #endif
    }

    private var content: some View {
        tabs
            .environment(\.startAnalysis) { startAnalysis() }
            .environment(\.showSettings) { showSettings() }
            .environment(\.openCoach, OpenCoachAction { analyzing = false; tab = .coach })
            .focusedSceneValue(\.sceneActions, SceneActions(tab: tab, selectTab: { tab = $0 }, startAnalysis: startAnalysis))
            .task {
                let store = HistoryStore(context: modelContext)
                try? store.recordOpenedDay()
                // Stored scores follow the current scoring rules.
                errors.attempt(.errorChangeFailed) { try store.rescoreAnalyses() }
                #if DEBUG
                await DemoData.seedIfRequested(context: modelContext, engine: engine, settings: settings)
                DemoData.exportIfRequested(context: modelContext, tint: theme.tint)
                switch DemoData.screen {
                case "practice": tab = .practice
                case "progress": tab = .progress
                case "coach": tab = .coach
                case "analysis": startAnalysis()
                case "settings": showSettings()
                case let name?: demoScreen = DemoScreen(name: name)
                default: break
                }
                #endif
            }
            // Its own task: it can take a minute and must not hold up the rest of launch.
            .task(priority: .utility) { await Reanalysis.run(context: modelContext, engine: engine, settings: settings.analyzer) }
            #if os(iOS)
            .fullScreenCover(isPresented: $analyzing) { AnalysisView().zoomDestination("analyze", in: zoom) }
            #endif
            #if os(iOS)
            .sheet(isPresented: $showsSettings) { SettingsView() }
            #endif
            #if DEBUG && os(iOS)
            .fullScreenCover(item: $demoScreen) { $0.view }
            #elseif DEBUG
            .sheet(item: $demoScreen) { $0.view.frame(minWidth: 600, minHeight: 760) }
            #endif
            // The sheet closes itself once onboarding is complete; it cannot be swiped away.
            .sheet(isPresented: Binding(get: { !settings.hasCompletedOnboarding }, set: { _ in })) { OnboardingView() }
            .errorAlerts(errors, isActive: !analyzing && !showsSettings && settings.hasCompletedOnboarding)
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab(value: AppTab.today) { TodayView() } label: { AppTab.today.label }
            Tab(value: AppTab.practice) { PracticeView() } label: { AppTab.practice.label }
            Tab(value: AppTab.progress) { ProgressTabView() } label: { AppTab.progress.label }
            Tab(value: AppTab.coach) { CoachView() } label: { AppTab.coach.label }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { AnalyzeAccessory { analyzing = true }.zoomSource("analyze", in: zoom) }
        #endif
    }
}

/// The global primary action above the tab bar.
private struct AnalyzeAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill").foregroundStyle(.tint)
                Text(.actionAnalyzeVoice).fontWeight(.semibold)
                if placement != .inline {
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.card)
    }
}

/// Toolbar items every tab's root shares: settings, and on Mac the primary analyze action.
struct RootToolbar: ToolbarContent {
    @Environment(\.showSettings) private var showSettings
    @Environment(\.startAnalysis) private var startAnalysis

    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button(action: startAnalysis) {
                Label { Text(.actionAnalyzeVoice) } icon: { Image(systemName: "mic.fill") }
            }
            .buttonStyle(.glassProminent)
        }
        #else
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: showSettings) {
                Label { Text(.navSettings) } icon: { Image(systemName: "gearshape") }
            }
        }
        #endif
    }
}
