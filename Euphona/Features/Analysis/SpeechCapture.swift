import Foundation
import Observation
import EuphonaKit

/// Records 16 kHz speech while counting valid speech live and drawing a smoothed amplitude per
/// 400 samples, for voice analysis and Voice Quality.
@MainActor @Observable
final class SpeechCapture {
    static let amplitudeBlock = 400

    let maximumSeconds: Double
    private(set) var elapsed: Double = 0
    private(set) var speechSeconds: Double = 0
    private(set) var amplitudes: [Float] = [0]
    private(set) var isRecording = false
    /// Live pitch for the orb's color.
    private(set) var pitch = PitchBalance()

    @ObservationIgnored private let microphone = MicrophoneCapture()
    @ObservationIgnored private let mode: MicrophoneCapture.Mode
    @ObservationIgnored private var samples: [Float] = []
    @ObservationIgnored private var pendingBlock: [Float] = []
    @ObservationIgnored private var counter = LiveSpeechCounter()
    @ObservationIgnored private var vadTask: Task<Void, Never>?
    @ObservationIgnored private var vadWindows: AsyncStream<LiveSpeechCounter.Window>.Continuation?
    @ObservationIgnored private var feedTask: Task<Void, Never>?
    @ObservationIgnored private var pitchChunks: AsyncStream<[Float]>.Continuation?

    init(maximumSeconds: Double, mode: MicrophoneCapture.Mode) {
        self.maximumSeconds = maximumSeconds
        self.mode = mode
    }

    /// Starts recording. `onLimit` runs when the maximum length is reached.
    func start(analyzer: EuphonaAnalyzer, onLimit: @escaping @MainActor () -> Void) throws {
        samples = []
        pendingBlock = []
        amplitudes = [0]
        elapsed = 0
        speechSeconds = 0
        counter = LiveSpeechCounter(normalizesLevel: mode == .measurement)
        startSpeechCounting(analyzer)
        startPitchTracking(analyzer)
        let (chunks, sink) = AsyncStream.makeStream(of: [Float].self)
        do {
            try microphone.start(mode: mode) { sink.yield($0) }
        } catch {
            vadWindows?.finish()
            pitchChunks?.finish()
            throw error
        }
        isRecording = true
        feedTask = Task { [weak self] in
            for await chunk in chunks {
                guard let self, self.isRecording else { return }
                self.ingest(chunk)
                if self.counter.recordedSeconds >= self.maximumSeconds {
                    onLimit()
                    return
                }
            }
        }
    }

    /// Stops, waits for the last VAD window, and returns the recording.
    func stop() async -> PCMBuffer {
        microphone.stop()
        isRecording = false
        feedTask?.cancel()
        pitchChunks?.finish()
        if let window = counter.finalWindow() { vadWindows?.yield(window) }
        vadWindows?.finish()
        await vadTask?.value
        speechSeconds = counter.speechSeconds
        return PCMBuffer(samples: SpeechLevel.apply(counter.levelGain, to: samples), sampleRate: MicrophoneCapture.sampleRate)
    }

    private func ingest(_ chunk: [Float]) {
        samples += chunk
        pendingBlock += chunk
        while pendingBlock.count >= Self.amplitudeBlock {
            let peak = pendingBlock.prefix(Self.amplitudeBlock).reduce(Float(0)) { max($0, abs($1)) }
            amplitudes.append((amplitudes.last ?? 0) * 0.45 + peak.squareRoot() * 0.55)
            pendingBlock.removeFirst(Self.amplitudeBlock)
        }
        for window in counter.append(chunk) { vadWindows?.yield(window) }
        pitchChunks?.yield(chunk)
        elapsed = min(counter.recordedSeconds, maximumSeconds)
    }

    /// The orb's balance now: the live pitch, eased back to `resting` in pauses.
    func orbBalance(resting: Double) -> Double {
        isRecording ? pitch.balance(at: elapsed, resting: resting) : resting
    }

    /// Realtime F0 at 30 frames/s on every chunk, in order; its clock is the recording's.
    private func startPitchTracking(_ analyzer: EuphonaAnalyzer) {
        pitch = PitchBalance()
        let (chunks, sink) = AsyncStream.makeStream(of: [Float].self)
        pitchChunks = sink
        Task { [weak self] in
            guard let stream = try? await offMain({ try RealtimeF0Stream(analyzer: analyzer, outputRateHz: 30) }) else { return }
            for await chunk in chunks {
                guard let frames = try? await offMain({ try stream.process(chunk) }), !frames.isEmpty else { continue }
                self?.pitch.ingest(frames)
            }
        }
    }

    /// VAD runs on each window in order, off the main actor, and feeds the merged speech total.
    private func startSpeechCounting(_ analyzer: EuphonaAnalyzer) {
        let (windows, sink) = AsyncStream.makeStream(of: LiveSpeechCounter.Window.self)
        vadWindows = sink
        vadTask = Task { [weak self] in
            for await window in windows {
                let segments = (try? await offMain {
                    try analyzer.detectSpeech(PCMBuffer(samples: window.samples, sampleRate: MicrophoneCapture.sampleRate))
                }) ?? []
                guard let self else { return }
                self.counter.record(segments, in: window)
                self.speechSeconds = self.counter.speechSeconds
            }
        }
    }
}
