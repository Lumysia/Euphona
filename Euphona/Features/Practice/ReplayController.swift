@preconcurrency import AVFAudio
import Observation
import EuphonaKit

/// Keeps the last 30 s of live audio and replays it a window at a time:
/// each rewind steps one window further back, playback runs forward to where live capture stopped,
/// the visible window pages along, and live capture resumes at the end.
@MainActor @Observable
final class ReplayController {
    static let historySeconds = 30.0
    static let endEpsilon = 0.01
    static let sampleRate = Double(MicrophoneCapture.sampleRate)

    let windowSeconds: Double
    private(set) var playhead: Double?
    private(set) var windowStart: Double?
    private(set) var tail: Double?
    /// Set briefly when the oldest audio is reached.
    private(set) var reachedLastPage = false

    @ObservationIgnored private var ring: [Float]
    @ObservationIgnored private var writeIndex = 0
    @ObservationIgnored private(set) var totalSamples = 0
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    init(windowSeconds: Double) {
        self.windowSeconds = windowSeconds
        ring = Array(repeating: 0, count: Int(Self.historySeconds * Self.sampleRate))
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    var isReplaying: Bool { playhead != nil }
    var liveEnd: Double { Double(totalSamples) / Self.sampleRate }
    private var oldest: Double { Double(max(0, totalSamples - ring.count)) / Self.sampleRate }

    func reset() {
        stop()
        writeIndex = 0
        totalSamples = 0
        ring = Array(repeating: 0, count: ring.count)
    }

    func append(_ samples: [Float]) {
        for sample in samples {
            ring[writeIndex] = sample
            writeIndex = (writeIndex + 1) % ring.count
        }
        totalSamples += samples.count
    }

    /// Steps one window back and plays from there. Returns the seconds behind live.
    @discardableResult
    func rewind(onFinished: @escaping @MainActor () -> Void) -> Double {
        let end = tail ?? liveEnd
        tail = end
        let target: (start: Double, last: Bool)
        if let current = windowStart, current <= oldest + Self.endEpsilon {
            target = (oldest, true)
        } else {
            let windowEnd = windowStart ?? end
            let start = max(oldest, windowEnd - windowSeconds)
            target = windowEnd - start <= Self.endEpsilon ? (oldest, true) : (start, start <= oldest + Self.endEpsilon)
        }
        if target.last { flagLastPage() }
        play(from: target.start, to: end, onFinished: onFinished)
        return end - target.start
    }

    func stop() {
        ticker?.cancel()
        player.stop()
        engine.stop()
        playhead = nil
        windowStart = nil
        tail = nil
    }

    private func play(from start: Double, to end: Double, onFinished: @escaping @MainActor () -> Void) {
        ticker?.cancel()
        player.stop()
        let samples = copy(from: start, to: end)
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        try? engine.start()
        player.scheduleBuffer(buffer)
        player.play()
        windowStart = start
        playhead = start
        let began = ContinuousClock.now
        ticker = Task { [weak self] in
            while !Task.isCancelled, let self {
                let position = start + (ContinuousClock.now - began) / .seconds(1)
                if position >= end - Self.endEpsilon {
                    self.stop()
                    onFinished()
                    return
                }
                self.playhead = position
                if let windowStart = self.windowStart, position > windowStart + self.windowSeconds {
                    self.windowStart = windowStart + self.windowSeconds
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func copy(from start: Double, to end: Double) -> [Float] {
        let first = max(Int(start * Self.sampleRate), totalSamples - ring.count)
        let last = min(Int(end * Self.sampleRate), totalSamples)
        guard last > first else { return [] }
        // Sample n lives at n % capacity, because writing started at index 0.
        return (first..<last).map { ring[$0 % ring.count] }
    }

    private func flagLastPage() {
        reachedLastPage = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.reachedLastPage = false
        }
    }
}
