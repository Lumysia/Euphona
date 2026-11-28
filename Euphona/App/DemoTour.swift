#if DEBUG
import EuphonaKit
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A scripted walk through the main flow, for App Review screen recordings (`-demo_tour 1`): Today, an
/// imported analysis (`-demo_import <file>`) and its result, the live pitch tool, Coach and Progress.
/// Pair it with `-demo_input <file>` so the pitch tool hears a file instead of the microphone, and with
/// `-demo_record <file>` so the app records itself (`DemoRecorder`); on iPhone and iPad a relative path is
/// in the app's Documents folder. Every step is logged (`DemoLog`).
///
/// On Mac the tour starts at launch and the app quits when it ends. On iPhone and iPad the person holding
/// the device starts it from a full-screen card (`DemoTourCard`), so iOS's recording consent comes only
/// after their tap; leaving the app for the background ends the take, keeping what was recorded, and the
/// card comes back for a new one. A take is written under its own name and becomes the `-demo_record` file only once the tour
/// ran to the end. Records the tour makes are dated after `-demo_tour_since <ISO 8601 date>` (default: this
/// launch) and are removed before each take, so the history on screen is the demo history plus one take.
@MainActor @Observable
final class DemoTour {
    static let shared = DemoTour()
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demo_tour") }

    enum Step { case idle, importAudio, openTool, startTool, closeTool, done }
    enum Phase { case off, ready, starting, recording, closing, finished }
    /// Why the card is back, shown on it.
    enum Setback { case leftApp, notStarted }

    /// What the views showing each part of the tour react to.
    private(set) var step: Step = .idle
    private(set) var phase: Phase = .off
    private(set) var setback: Setback?
    /// Set by the analysis once its result is on screen.
    var analysisFinished = false

    struct Actions {
        var selectTab: (AppTab) -> Void
        var startAnalysis: () -> Void
        var closeAnalysis: () -> Void
        var context: ModelContext
    }

    private var actions: Actions?
    private var take: Task<Void, Never>?
    private var recorder: DemoRecorder?
    private var observers: [NSObjectProtocol] = []
    private let since: Date = UserDefaults.standard.string(forKey: "demo_tour_since")
        .flatMap { try? Date($0, strategy: .iso8601) } ?? .now

    /// A launch argument's file; a relative path is looked up in the app bundle.
    static func file(_ key: String) -> URL? {
        UserDefaults.standard.string(forKey: key).map { path in
            path.hasPrefix("/") ? URL(filePath: path) : Bundle.main.bundleURL.appending(path: path)
        }
    }

    /// Called once the app's first screen is up.
    func start(_ actions: Actions) {
        guard Self.isOn, phase == .off else { return }
        self.actions = actions
        DemoLog.write("launch: tour on, record to \(Self.recording?.lastPathComponent ?? "nothing"), tour records after \(since.formatted(.iso8601))")
        if let final = Self.recording { Self.moveAside(final) }
        #if os(macOS)
        record()
        #else
        UIApplication.shared.isIdleTimerDisabled = true
        observeLifecycle()
        phase = .ready
        DemoLog.write("start card shown")
        #endif
    }

    /// The start card's tap.
    func begin() {
        guard phase == .ready else { return }
        DemoLog.write("start card tapped")
        record()
    }

    private func record() {
        phase = .starting
        setback = nil
        take = Task { await recordTake() }
    }

    private func recordTake() async {
        guard let actions else { return }
        reset(actions)
        removeEarlierTakes(actions.context)
        let final = Self.recording
        let url = final.map(Self.takeFile)
        do {
            if let url { recorder = try await DemoRecorder.start(to: url) }
        } catch {
            DemoLog.write("recording did not start: \(DemoLog.describe(error))")
            endWithoutTake(.notStarted)
            return
        }
        #if os(iOS)
        // Left while the consent alert was up.
        guard UIApplication.shared.applicationState != .background else {
            phase = .recording
            interrupt("app in the background when capture started")
            return
        }
        #endif
        phase = .recording
        DemoLog.write("tour started")
        do { try await tour(actions) } catch {
            // Cancelled by `interrupt`, which closes the file.
            return
        }
        phase = .closing
        let complete = await recorder?.stop() ?? false
        recorder = nil
        if let url, let final, complete {
            do {
                try FileManager.default.moveItem(at: url, to: final)
                DemoLog.write("take finished: \(final.lastPathComponent)")
            } catch {
                DemoLog.write("could not name the take \(final.lastPathComponent): \(DemoLog.describe(error))")
            }
        } else {
            DemoLog.write("tour finished without a complete recording")
        }
        phase = .finished
        #if os(macOS)
        NSApp.terminate(nil)
        #else
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    private func tour(_ actions: Actions) async throws {
        try await pause(5)
        actions.startAnalysis()
        try await pause(3.5)
        step = .importAudio
        for _ in 0..<240 where !analysisFinished { try await pause(0.25) }
        DemoLog.write(analysisFinished ? "analysis finished" : "analysis still running after 60 s")
        try await pause(12)
        actions.closeAnalysis()
        try await pause(2.5)
        actions.selectTab(.practice)
        try await pause(3)
        step = .openTool
        try await pause(2.5)
        step = .startTool
        DemoLog.write("pitch tool live")
        try await pause(14)
        step = .closeTool
        try await pause(2)
        actions.selectTab(.coach)
        try await pause(7)
        actions.selectTab(.progress)
        DemoLog.write("progress")
        try await pause(8)
        step = .done
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Back to Today with nothing open, as at launch.
    private func reset(_ actions: Actions) {
        actions.closeAnalysis()
        step = .idle
        analysisFinished = false
        actions.selectTab(.today)
    }

    private func removeEarlierTakes(_ context: ModelContext) {
        let since = since
        do {
            let analyses = try context.fetch(FetchDescriptor<AnalysisRecord>(predicate: #Predicate { $0.date > since }))
            let sessions = try context.fetch(FetchDescriptor<PitchSession>(predicate: #Predicate { $0.date > since }))
            analyses.forEach { context.delete($0) }
            sessions.forEach { context.delete($0) }
            try context.save()
            if analyses.count + sessions.count > 0 {
                DemoLog.write("removed records of earlier takes: \(analyses.count) analyses, \(sessions.count) pitch sessions")
            }
        } catch {
            DemoLog.write("could not remove earlier takes' records: \(DemoLog.describe(error))")
        }
    }

    private func endWithoutTake(_ reason: Setback) {
        recorder = nil
        #if os(macOS)
        NSApp.terminate(nil)
        #else
        if let actions { reset(actions) }
        setback = reason
        phase = .ready
        DemoLog.write("start card shown again")
        #endif
    }

    /// Where the finished take goes, with the recorder's file type.
    private static var recording: URL? {
        UserDefaults.standard.string(forKey: "demo_record").map { path in
            let url = path.hasPrefix("/") ? URL(filePath: path) : URL.documentsDirectory.appending(path: path)
            return url.deletingPathExtension().appendingPathExtension(DemoRecorder.fileExtension)
        }
    }

    /// A take's own file beside the finished one.
    private static func takeFile(for final: URL) -> URL {
        sibling(of: final, tag: "take")
    }

    /// A finished take from an earlier launch keeps its content under another name.
    private static func moveAside(_ final: URL) {
        guard FileManager.default.fileExists(atPath: final.path) else { return }
        let earlier = sibling(of: final, tag: "earlier")
        try? FileManager.default.moveItem(at: final, to: earlier)
        DemoLog.write("moved an earlier \(final.lastPathComponent) to \(earlier.lastPathComponent)")
    }

    private static func sibling(of url: URL, tag: String) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appending(path: "\(stem)-\(tag)-\(Int(Date.now.timeIntervalSince1970)).\(url.pathExtension)")
    }

    #if os(iOS)
    private func observeLifecycle() {
        let events: [(Notification.Name, String)] = [
            (UIApplication.willResignActiveNotification, "will resign active"),
            (UIApplication.didEnterBackgroundNotification, "entered background"),
            (UIApplication.willEnterForegroundNotification, "will enter foreground"),
            (UIApplication.didBecomeActiveNotification, "became active"),
        ]
        observers = events.map { name, label in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.lifecycle(name, label) }
            }
        }
    }

    /// Only going to the background ends a take: iOS also resigns the app for a moment when its
    /// recording consent closes, or while Control Center is open, and capture goes on through those.
    private func lifecycle(_ name: Notification.Name, _ label: String) {
        DemoLog.write("app \(label) (\(phase))")
        if name == UIApplication.didEnterBackgroundNotification { interrupt("app left") }
    }

    /// Ends a running take: the tour stops, the file written so far is closed, and the card comes back.
    private func interrupt(_ reason: String) {
        guard phase == .recording else { return }
        DemoLog.write("take interrupted: \(reason)")
        take?.cancel()
        take = nil
        let recorder = recorder
        let background = UIApplication.shared.beginBackgroundTask(withName: "Close review take")
        Task {
            _ = await recorder?.stop()
            UIApplication.shared.endBackgroundTask(background)
        }
        endWithoutTake(.leftApp)
    }
    #endif
}

#if os(iOS)
/// What the person holding the device sees before and after a take, in English and Chinese, since they
/// start it themselves and nothing outside the app explains it. Debug only, so not localized.
struct DemoTourCard: View {
    private let tour = DemoTour.shared

    var body: some View {
        switch tour.phase {
        case .ready:
            Button(action: tour.begin) {
                card(symbol: "record.circle", tint: .red, lines: [
                    "Tap to start the review recording.",
                    "Then put the phone down for about 3 minutes.",
                    "点一下开始录制审核视频，然后把手机放下大约 3 分钟。",
                ], note: note)
            }
            .buttonStyle(.plain)
        case .finished:
            card(symbol: "checkmark.circle.fill", tint: .green, lines: [
                "Done, you can take the phone back.",
                "录好了，可以把手机拿回去了。",
            ], note: nil)
        case .off, .starting, .recording, .closing:
            EmptyView()
        }
    }

    private var note: String {
        switch tour.setback {
        case .leftApp: "The last take stopped when the app was left. Stay in Euphona until it says Done.\n上一次离开 Euphona 时停了，录完之前请留在 Euphona 里。"
        case .notStarted: "Recording didn't start. When iOS asks, choose Record Screen.\n录制没有开始。系统询问时请选“录制屏幕”。"
        case nil: "When iOS asks, choose Record Screen.\n系统询问时请选“录制屏幕”。"
        }
    }

    private func card(symbol: String, tint: Color, lines: [String], note: String?) -> some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 72))
                .foregroundStyle(tint)
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line).font(.title2.weight(.semibold))
            }
            if let note {
                Text(verbatim: note).font(.body).foregroundStyle(.secondary).padding(.top, 12)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contentShape(Rectangle())
    }
}
#endif
#endif
