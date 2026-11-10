import Foundation
import Observation
import EuphonaKit
import SwiftData

/// Live pitch: microphone → realtime F0 → points, with rewind and a session summary.
@MainActor @Observable
final class PitchMonitor {
    static let windowSeconds = 3.0
    static let maximumPoints = 1880
    static let liveHoldSeconds = 2.0
    static let replayHoldSeconds = 0.15

    struct Point: Equatable {
        var time: Double
        var hz: Double?
    }

    enum State { case idle, preparing, running, paused }

    private(set) var state: State = .idle
    private(set) var points: [Point] = []
    private(set) var failure: CaptureFailure?
    let replay = ReplayController(windowSeconds: windowSeconds)

    @ObservationIgnored private let capture = MicrophoneCapture()
    @ObservationIgnored private var stream: RealtimeF0Stream?
    @ObservationIgnored private var feed: Task<Void, Never>?
    @ObservationIgnored private var sum = 0.0
    @ObservationIgnored private var count = 0

    /// The pitch to show: during replay the point under the playhead, live the last voiced point
    /// unless it is more than 2 s old.
    var currentHz: Double? {
        if let playhead = replay.playhead {
            guard let point = points.last(where: { $0.time <= playhead }), playhead - point.time <= Self.replayHoldSeconds else { return nil }
            return point.hz
        }
        guard state == .running || state == .paused, let latest = points.last,
              let voiced = points.last(where: { $0.hz != nil }), latest.time - voiced.time <= Self.liveHoldSeconds else { return nil }
        return voiced.hz
    }

    /// Share of this session's voiced points on `target`.
    func share(on target: PitchTarget) -> Double? {
        PitchTarget.share(points.compactMap { point in point.hz.map { (point.time, $0) } }, on: target)
    }

    /// The right edge of the visible window.
    var windowEnd: Double {
        if let start = replay.windowStart { return start + Self.windowSeconds }
        return points.last?.time ?? 0
    }

    func start(engine: VoiceEngine, settings: AppSettings) async {
        guard state == .idle || state == .paused else { return }
        replay.stop()
        failure = nil
        guard await MicrophoneCapture.requestPermission() else { failure = .microphoneDenied; return }
        state = .preparing
        do {
            if stream == nil {
                let analyzer = try await engine.analyzer(for: settings.analyzer)
                let rate = settings.f0SampleRate
                stream = try await offMain { try RealtimeF0Stream(analyzer: analyzer, outputRateHz: Double(rate)) }
            }
            guard let stream else { return }
            let (chunks, sink) = AsyncStream.makeStream(of: [Float].self)
            try capture.start(mode: .measurement) { sink.yield($0) }
            state = .running
            feed = Task { [weak self] in
                for await chunk in chunks {
                    guard let self else { return }
                    self.replay.append(chunk)
                    guard let frames = try? await offMain({ try stream.process(chunk) }) else { continue }
                    self.ingest(frames)
                }
            }
        } catch {
            failure = .couldNotStart
            state = .idle
        }
    }

    func pause() {
        guard state == .running || state == .preparing else { return }
        capture.stop()
        feed?.cancel()
        state = .paused
    }

    /// Steps back one window and plays it; live analysis resumes at the end.
    func rewind(engine: VoiceEngine, settings: AppSettings) {
        guard state != .idle, !points.isEmpty else { return }
        pause()
        replay.rewind { [weak self] in
            Task { await self?.start(engine: engine, settings: settings) }
        }
    }

    /// Stops and saves the session's mean pitch, if anything was voiced.
    func finish(context: ModelContext) {
        capture.stop()
        feed?.cancel()
        replay.stop()
        if count > 0 { try? HistoryStore(context: context).addPitchSession(meanF0Hz: sum / Double(count)) }
        sum = 0
        count = 0
        stream = nil
        points = []
        replay.reset()
        state = .idle
    }

    private func ingest(_ frames: [F0Frame]) {
        for frame in frames {
            let hz = frame.voiced && frame.f0Hz.isFinite ? Double(frame.f0Hz) : nil
            if let hz { sum += hz; count += 1 }
            points.append(Point(time: frame.timestamp, hz: hz))
        }
        if points.count > Self.maximumPoints { points.removeFirst(points.count - Self.maximumPoints) }
    }
}
