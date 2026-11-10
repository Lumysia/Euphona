import EuphonaKit
import SwiftData
import SwiftUI

@main
struct EuphonaApp: App {
    @State private var settings: AppSettings
    @State private var engine = VoiceEngine()
    @State private var history: HistoryContainer
    @State private var errors = ErrorCenter()

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _history = State(initialValue: HistoryContainer(syncs: settings.syncsWithICloud))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(engine)
                .tint(settings.palette.tint)
                .environment(\.theme, ThemeColors(settings.palette))
                .modelContainer(history.container)
                .environment(errors)
                .onChange(of: settings.syncsWithICloud) { history.setSyncs(settings.syncsWithICloud) }
                .onChange(of: history.isTemporary, initial: true) {
                    if history.isTemporary { errors.report(.errorStoreUnavailable, message: .errorStoreUnavailableMessage) }
                }
        }
        .commands { AppCommands() }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif

        #if os(macOS)
        // On Mac, voice analysis is its own window, centered, like a new recording in QuickTime.
        Window(Text(.feedbackTitle), id: FeedbackView.windowID) {
            NavigationStack { FeedbackView() }
                .frame(minWidth: 460, minHeight: 560)
                .environment(settings)
                .tint(settings.palette.tint)
                .environment(\.theme, ThemeColors(settings.palette))
                .modelContainer(history.container)
        }
        .windowResizability(.contentSize)

        Window(Text(.analysisInferenceTitle), id: AnalysisView.windowID) {
            AnalysisView()
                .environment(settings)
                .environment(engine)
                .tint(settings.palette.tint)
                .environment(\.theme, ThemeColors(settings.palette))
                .frame(minWidth: 480, minHeight: 680)
                .modelContainer(history.container)
                .environment(errors)
                .errorAlerts(errors)
        }
        .defaultSize(width: 560, height: 800)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(settings)
                .tint(settings.palette.tint)
                .environment(\.theme, ThemeColors(settings.palette))
                .frame(width: 560)
                .modelContainer(history.container)
                .environment(errors)
                .errorAlerts(errors)
        }
        #endif
    }
}

/// The menu bar on Mac and the keyboard shortcut menu on iPad: File ▸ Analyze Voice (⌘R), and
/// View ▸ one item per tab (⌘1…).
private struct AppCommands: Commands {
    @FocusedValue(\.sceneActions) private var actions
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(action: analyze) { Text(.actionAnalyzeVoice) }
                .keyboardShortcut("r", modifiers: .command)
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Toggle(isOn: Binding(get: { actions?.tab == tab }, set: { _ in actions?.selectTab(tab) })) {
                    Text(tab.title)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .disabled(actions == nil)
            }
            Divider()
        }
        #if os(macOS)
        CommandGroup(replacing: .help) {
            Button { openWindow(id: FeedbackView.windowID) } label: { Text(.feedbackMenu) }
        }
        #endif
    }

    /// On Mac the analysis window opens even when no main window is in front.
    private func analyze() {
        #if os(macOS)
        openWindow(id: AnalysisView.windowID)
        #else
        actions?.startAnalysis()
        #endif
    }
}
