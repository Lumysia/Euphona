@preconcurrency import AVFAudio
import Foundation

/// Captures the microphone as 16 kHz mono float PCM, the format the analysis streams take.
public final class MicrophoneCapture: @unchecked Sendable {
    public static let sampleRate = 16_000

    /// `voice` keeps the system's voice processing for analyses; `measurement` turns it off for pitch,
    /// spectrum and Voice Quality, which need the unprocessed signal.
    public enum Mode: Sendable { case voice, measurement }

    public enum Failure: Error { case permissionDenied, noInput }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var running = false

    public init() {}

    public static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Starts capturing. `onSamples` runs on the audio thread with each converted chunk.
    public func start(mode: Mode, onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        guard AVAudioApplication.shared.recordPermission == .granted else { throw Failure.permissionDenied }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: mode == .voice ? .default : .measurement,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        #endif
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Self.sampleRate),
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target)
        else { throw Failure.noInput }

        let ratio = target.sampleRate / inputFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            nonisolated(unsafe) var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, output.frameLength > 0, let data = output.floatChannelData?[0] else { return }
            onSamples(Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength))))
        }
        engine.prepare()
        try engine.start()
        lock.withLock { running = true }
    }

    public func stop() {
        let wasRunning = lock.withLock { () -> Bool in
            defer { running = false }
            return running
        }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    deinit { stop() }
}
