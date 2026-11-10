import Observation
import EuphonaKit

/// The microphone side of a live tool: permission, start and stop, the failure to show, and a feed
/// that hands each chunk to the tool in order.
@MainActor @Observable
final class LiveInput {
    enum State { case idle, preparing, running }

    private(set) var state: State = .idle
    private(set) var failure: CaptureFailure?

    @ObservationIgnored private let capture = MicrophoneCapture()
    @ObservationIgnored private var feed: Task<Void, Never>?

    var isRunning: Bool { state != .idle }

    /// `prepare` runs once before listening (loading a model); `chunk` gets every 16 kHz chunk in order.
    func start(mode: MicrophoneCapture.Mode, prepare: () async throws -> Void = {},
               chunk: @escaping @MainActor ([Float]) async -> Void) async {
        guard state == .idle else { return }
        failure = nil
        guard await MicrophoneCapture.requestPermission() else { failure = .microphoneDenied; return }
        state = .preparing
        do {
            try await prepare()
            let (chunks, sink) = AsyncStream.makeStream(of: [Float].self)
            try capture.start(mode: mode) { sink.yield($0) }
            state = .running
            feed = Task { [weak self] in
                for await samples in chunks {
                    guard let self, !Task.isCancelled else { return }
                    await chunk(samples)
                }
            }
        } catch {
            failure = .couldNotStart
            state = .idle
        }
    }

    func stop() {
        capture.stop()
        feed?.cancel()
        feed = nil
        state = .idle
    }
}
