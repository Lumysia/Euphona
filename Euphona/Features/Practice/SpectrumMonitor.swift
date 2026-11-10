import CoreGraphics
import Foundation
import Observation
import EuphonaKit

/// Live spectrum: microphone → spectrum → 256 log bands per frame, with rewind.
@MainActor @Observable
final class SpectrumMonitor {
    static let windowSeconds = 5.0
    static let historySeconds = 30.0

    enum State { case idle, preparing, running, paused }

    private(set) var state: State = .idle
    /// The visible window as an image, newest on the right.
    private(set) var image: CGImage?
    private(set) var hasSignal = false
    /// The strongest frequency in the newest frame, when anything is louder than the floor.
    private(set) var peakHz: Double?
    private(set) var failure: CaptureFailure?
    let replay = ReplayController(windowSeconds: windowSeconds)

    @ObservationIgnored private let capture = MicrophoneCapture()
    @ObservationIgnored private var spectrum: SpectrumStream?
    @ObservationIgnored private var feed: Task<Void, Never>?
    @ObservationIgnored private var columns: [(time: Double, bands: [Float])] = []
    @ObservationIgnored private var frameRate: Double = 62.5

    func start() async {
        guard state == .idle || state == .paused else { return }
        replay.stop()
        failure = nil
        guard await MicrophoneCapture.requestPermission() else { failure = .microphoneDenied; return }
        state = .preparing
        do {
            if spectrum == nil { spectrum = SpectrumStream() }
            guard let spectrum else { return }
            frameRate = Double(MicrophoneCapture.sampleRate) / Double(spectrum.options.hopSamples)
            let (chunks, sink) = AsyncStream.makeStream(of: [Float].self)
            try capture.start(mode: .measurement) { sink.yield($0) }
            state = .running
            feed = Task { [weak self] in
                for await chunk in chunks {
                    guard let self else { return }
                    self.replay.append(chunk)
                    guard let (frames, peak) = try? await offMain({
                        let frames = spectrum.process(chunk)
                        return (frames.map { ($0.timestamp, SpectrumBands.bands(of: $0)) }, frames.last.flatMap(Self.peak))
                    }) else { continue }
                    if !frames.isEmpty { self.peakHz = peak }
                    self.columns += frames
                    let cutoff = (self.columns.last?.time ?? 0) - Self.historySeconds
                    self.columns.removeAll { $0.time < cutoff }
                    self.render()
                }
            }
        } catch {
            failure = .couldNotStart
            state = .idle
        }
    }

    nonisolated static func peak(_ frame: SpectrumFrame) -> Double? {
        guard let index = frame.magnitudes.indices.max(by: { frame.magnitudes[$0] < frame.magnitudes[$1] }),
              frame.magnitudes[index] > SpectrumBands.floorDb + 25 else { return nil }
        return Double(index + frame.firstBinIndex) * Double(frame.binHz)
    }

    func pause() {
        guard state == .running || state == .preparing else { return }
        capture.stop()
        feed?.cancel()
        state = .paused
    }

    func rewind() {
        guard state != .idle, !columns.isEmpty else { return }
        pause()
        replay.rewind { [weak self] in Task { await self?.start() } }
        render()
        replayTicker = Task { [weak self] in
            while let self, self.replay.isReplaying, !Task.isCancelled {
                self.render()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    @ObservationIgnored private var replayTicker: Task<Void, Never>?

    func stop() {
        capture.stop()
        feed?.cancel()
        replayTicker?.cancel()
        replay.reset()
        spectrum = nil
        columns = []
        image = nil
        state = .idle
    }

    /// Paints the 5 s window ending at the newest frame, or at the replay window's end.
    private func render() {
        let width = Int(Self.windowSeconds * frameRate)
        let height = SpectrumBands.count
        let end = replay.windowStart.map { $0 + Self.windowSeconds } ?? columns.last?.time ?? 0
        let start = end - Self.windowSeconds
        let background = SpectrumBands.color(0)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for x in 0..<width {
                let offset = (row * width + x) * 4
                pixels[offset] = background.0; pixels[offset + 1] = background.1; pixels[offset + 2] = background.2
            }
        }
        var any = false
        for column in columns where column.time > start && column.time <= end {
            let x = min(width - 1, Int((column.time - start) / Self.windowSeconds * Double(width)))
            for row in 0..<height {
                let level = SpectrumBands.level(column.bands[row])
                if level > 0.05 { any = true }
                let color = SpectrumBands.color(level)
                let offset = (row * width + x) * 4
                pixels[offset] = color.0; pixels[offset + 1] = color.1; pixels[offset + 2] = color.2
            }
        }
        hasSignal = any
        image = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
    }
}
