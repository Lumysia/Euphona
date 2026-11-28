#if DEBUG
import SwiftUI
#if os(macOS)
import ScreenCaptureKit
#else
import ReplayKit
import UIKit
#endif

/// A scripted walk through the main flow, for App Review screen recordings (`-demo_tour 1`): Today, an
/// imported analysis (`-demo_import <file>`) and its result, the live pitch tool, Coach and Progress.
/// Pair it with `-demo_input <file>` so the pitch tool hears a file instead of the microphone. On Mac,
/// `-demo_record <file.mp4>` records the app's own screen during the tour (and on Mac quits when it ends);
/// on iPhone and iPad a relative path is in the app's Documents folder.
@MainActor @Observable
final class DemoTour {
    static let shared = DemoTour()
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demo_tour") }

    enum Step { case idle, importAudio, openTool, startTool, closeTool, done }

    /// What the views showing each part of the tour react to.
    private(set) var step: Step = .idle
    /// Set by the analysis once its result is on screen.
    var analysisFinished = false

    struct Actions {
        var selectTab: (AppTab) -> Void
        var startAnalysis: () -> Void
        var closeAnalysis: () -> Void
    }

    /// A launch argument's file; a relative path is looked up in the app bundle.
    static func file(_ key: String) -> URL? {
        UserDefaults.standard.string(forKey: key).map { path in
            path.hasPrefix("/") ? URL(filePath: path) : Bundle.main.bundleURL.appending(path: path)
        }
    }

    func run(_ actions: Actions) async {
        guard Self.isOn, step == .idle else { return }
        actions.selectTab(.today)
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
        let recorder = await Self.recording.asyncMap { await DemoRecorder.start(to: $0) } ?? nil
        await pause(5)
        actions.startAnalysis()
        await pause(3.5)
        step = .importAudio
        for _ in 0..<240 where !analysisFinished { await pause(0.25) }
        await pause(12)
        actions.closeAnalysis()
        await pause(2.5)
        actions.selectTab(.practice)
        await pause(3)
        step = .openTool
        await pause(2.5)
        step = .startTool
        await pause(14)
        step = .closeTool
        await pause(2)
        actions.selectTab(.coach)
        await pause(7)
        actions.selectTab(.progress)
        await pause(8)
        step = .done
        await recorder?.stop()
        #if os(macOS)
        NSApp.terminate(nil)
        #else
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }

    private static var recording: URL? {
        #if os(macOS)
        file("demo_record")
        #else
        UserDefaults.standard.string(forKey: "demo_record").map { path in
            path.hasPrefix("/") ? URL(filePath: path) : URL.documentsDirectory.appending(path: path)
        }
        #endif
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}

#if os(macOS)
/// Records the app's own windows (nothing else on screen) with ScreenCaptureKit, which needs no screen
/// recording permission for a process's own content. The main window moves to a fixed frame in the
/// middle of the screen and every window opened later takes the same frame, so the video is one steady
/// window-sized picture.
@MainActor
final class DemoRecorder: NSObject, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Never>?
    private var observer: NSObjectProtocol?

    static func start(to url: URL) async -> DemoRecorder? {
        let recorder = DemoRecorder()
        return await recorder.begin(url) ? recorder : nil
    }

    private func begin(_ url: URL) async -> Bool {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
              let screen = window.screen else { return false }
        let visible = screen.visibleFrame
        let size = NSSize(width: min(1180, visible.width - 40), height: min(820, visible.height - 40))
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                           width: size.width, height: size.height).integral
        window.setFrame(frame, display: true)
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                                          queue: .main) { note in
            guard let opened = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                if opened.styleMask.contains(.titled), opened.frame != frame { opened.setFrame(frame, display: true) }
            }
        }
        do {
            let content = try await SCShareableContent.currentProcess
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
            else { return false }
            // The whole app, so windows it opens later are in the picture too.
            let filter = SCContentFilter(display: display, including: content.applications, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
                                       width: frame.width, height: frame.height)
            config.width = Int(frame.width * screen.backingScaleFactor)
            config.height = Int(frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.capturesAudio = false
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let output = SCRecordingOutputConfiguration()
            output.outputURL = url
            output.outputFileType = .mp4
            try? FileManager.default.removeItem(at: url)
            try stream.addRecordingOutput(SCRecordingOutput(configuration: output, delegate: self))
            try await stream.startCapture()
            self.stream = stream
            return true
        } catch {
            return false
        }
    }

    func stop() async {
        guard let stream else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        await withCheckedContinuation { continuation in
            finished = continuation
            Task { try? await stream.stopCapture() }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in self.finish() }
    }

    private func finish() {
        finished?.resume()
        finished = nil
    }
}
#else
/// Records the app's own screen with ReplayKit, without microphone or camera. The system asks once
/// before the first recording.
@MainActor
final class DemoRecorder {
    private let url: URL

    private init(url: URL) { self.url = url }

    static func start(to url: URL) async -> DemoRecorder? {
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        do { try await recorder.startRecording() } catch { return nil }
        return DemoRecorder(url: url)
    }

    func stop() async {
        try? FileManager.default.removeItem(at: url)
        try? await RPScreenRecorder.shared().stopRecording(withOutput: url)
    }
}
#endif
#endif
