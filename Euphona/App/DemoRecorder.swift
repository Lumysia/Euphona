#if DEBUG
import AVFoundation
#if os(macOS)
import AppKit
import ScreenCaptureKit
#else
import ReplayKit
#endif

#if os(macOS)
/// Records the app's own windows (nothing else on screen) with ScreenCaptureKit, which needs no screen
/// recording permission for a process's own content. The main window moves to a fixed frame in the
/// middle of the screen and every window opened later takes the same frame, so the video is one steady
/// window-sized picture.
@MainActor
final class DemoRecorder: NSObject, SCRecordingOutputDelegate {
    static let fileExtension = "mp4"
    enum Failure: Error { case noWindow, noDisplay }

    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Never>?
    private var observer: NSObjectProtocol?
    private var failed = false

    static func start(to url: URL) async throws -> DemoRecorder {
        let recorder = DemoRecorder()
        try await recorder.begin(url)
        return recorder
    }

    private func begin(_ url: URL) async throws {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
              let screen = window.screen else { throw Failure.noWindow }
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
        let content = try await SCShareableContent.currentProcess
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
        else { throw Failure.noDisplay }
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
        try stream.addRecordingOutput(SCRecordingOutput(configuration: output, delegate: self))
        try await stream.startCapture()
        self.stream = stream
    }

    /// Ends the capture and closes the file. Returns whether the file is complete.
    func stop() async -> Bool {
        guard let stream else { return false }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        await withCheckedContinuation { continuation in
            finished = continuation
            Task { try? await stream.stopCapture() }
        }
        return !failed
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finish(failed: false) }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        DemoLog.write("recording failed: \(DemoLog.describe(error))")
        Task { @MainActor in self.finish(failed: true) }
    }

    private func finish(failed: Bool) {
        self.failed = self.failed || failed
        finished?.resume()
        finished = nil
    }
}
#else
/// Records the app's own screen with ReplayKit's capture, without microphone or camera, into a QuickTime
/// movie written in one-second fragments: a take cut short (the app left, the process ended) still plays
/// up to where it stopped. iOS asks before the first capture.
nonisolated final class DemoRecorder: NSObject, RPScreenRecorderDelegate, @unchecked Sendable {
    static let fileExtension = "mov"

    private let url: URL
    /// Guards everything below: frames arrive on ReplayKit's queue.
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var triedWriter = false
    private var closed = false
    private var frames = 0
    private var dropped = 0
    private var captureError: String?

    private init(url: URL) { self.url = url }

    @MainActor static func start(to url: URL) async throws -> DemoRecorder {
        let recorder = DemoRecorder(url: url)
        let screen = RPScreenRecorder.shared()
        screen.isMicrophoneEnabled = false
        screen.isCameraEnabled = false
        screen.delegate = recorder
        DemoLog.write("ReplayKit available: \(screen.isAvailable); starting capture (iOS may ask)")
        try? FileManager.default.removeItem(at: url)
        try await screen.startCapture { @Sendable buffer, type, error in recorder.received(buffer, type, error) }
        DemoLog.write("capture started")
        return recorder
    }

    private func received(_ buffer: CMSampleBuffer, _ type: RPSampleBufferType, _ error: (any Error)?) {
        lock.withLock {
            if let error, captureError == nil {
                captureError = DemoLog.describe(error)
                DemoLog.write("capture error: \(DemoLog.describe(error))")
            }
            guard !closed, error == nil, type == .video, buffer.isValid, buffer.dataReadiness == .ready else { return }
            if !triedWriter { openWriter(with: buffer) }
            guard let writer, let input, writer.status == .writing else { return }
            if input.isReadyForMoreMediaData, input.append(buffer) { frames += 1 } else { dropped += 1 }
        }
    }

    /// Made with the first frame, which gives the picture's size.
    private func openWriter(with buffer: CMSampleBuffer) {
        triedWriter = true
        guard let format = buffer.formatDescription else { return }
        let size = CMVideoFormatDescriptionGetDimensions(format)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            self.writer = writer
            self.input = input
            DemoLog.write("first frame \(size.width)x\(size.height), writing \(url.lastPathComponent)")
        } catch {
            DemoLog.write("writer did not start: \(DemoLog.describe(error))")
        }
    }

    /// Ends the capture and closes the file. Returns whether the file is complete.
    func stop() async -> Bool {
        let stopError: (any Error)? = await withCheckedContinuation { done in
            RPScreenRecorder.shared().stopCapture { done.resume(returning: $0) }
        }
        if let stopError { DemoLog.write("stopCapture: \(DemoLog.describe(stopError))") }
        let (writer, input, frames, dropped) = lock.withLock {
            closed = true
            return (self.writer, self.input, self.frames, self.dropped)
        }
        guard let writer, let input, writer.status == .writing else {
            DemoLog.write("nothing written (\(frames) frames, writer \(writer.map { "\($0.status.rawValue)" } ?? "never opened"))")
            return false
        }
        input.markAsFinished()
        await writer.finishWriting()
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let state = writer.status == .completed ? "complete" : "status \(writer.status.rawValue) \(writer.error.map(DemoLog.describe) ?? "")"
        DemoLog.write("file \(url.lastPathComponent) closed: \(state), \(frames) frames, \(dropped) dropped, \(bytes) bytes")
        return writer.status == .completed
    }

    func screenRecorder(_ screenRecorder: RPScreenRecorder, didStopRecordingWith previewViewController: RPPreviewViewController?,
                        error: (any Error)?) {
        DemoLog.write("ReplayKit stopped the capture: \(error.map(DemoLog.describe) ?? "no error")")
    }

    func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        DemoLog.write("ReplayKit available: \(screenRecorder.isAvailable)")
    }
}
#endif
#endif
