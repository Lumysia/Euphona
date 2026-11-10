import Accelerate
import Foundation
import Synchronization

public struct SpectrumFrame: Sendable {
    public var timestamp: Double
    /// dBFS per FFT bin (a full-scale sine reads 0 dB), starting at `firstBinIndex`.
    public var magnitudes: [Float]
    public var firstBinIndex: Int
    public var binHz: Float
}

/// Live spectrum of 16 kHz mono audio: Hann-windowed FFTs every hop, smoothed over time in dB.
public final class SpectrumStream: Sendable {
    public struct Options: Sendable {
        public var fftSize = 4096
        public var hopSamples = 256
        public var minHz = 40
        public var maxHz = 8000
        /// Share of the previous frame kept in each new one.
        public var smoothing: Float = 0.35

        public init() {}
    }

    private struct State {
        var buffer: [Float] = []
        var sinceLast = 0
        var produced = 0
        var previous: [Float]?
    }

    public let options: Options
    private let fft: RealFFT
    private let window: [Float]
    private let bins: ClosedRange<Int>
    private let state = Mutex(State())

    public init(options: Options = Options()) {
        self.options = options
        fft = RealFFT(size: options.fftSize)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: options.fftSize, isHalfWindow: false)
        let binHz = Float(SpeechDetector.sampleRate) / Float(options.fftSize)
        bins = max(1, Int((Float(options.minHz) / binHz).rounded(.up)))...min(options.fftSize / 2, Int(Float(options.maxHz) / binHz))
    }

    public func process(_ samples: [Float]) -> [SpectrumFrame] {
        state.withLock { s in
            s.buffer += samples
            s.sinceLast += samples.count
            var frames: [SpectrumFrame] = []
            while s.sinceLast >= options.hopSamples {
                s.sinceLast -= options.hopSamples
                s.produced += 1
                let end = s.buffer.count - s.sinceLast
                guard end >= options.fftSize else { continue }
                frames.append(frame(s.buffer[(end - options.fftSize)..<end], state: &s))
            }
            if s.buffer.count > options.fftSize + options.hopSamples {
                s.buffer.removeFirst(s.buffer.count - options.fftSize - options.hopSamples)
            }
            return frames
        }
    }

    public func reset() {
        state.withLock { $0 = State() }
    }

    private func frame(_ x: ArraySlice<Float>, state s: inout State) -> SpectrumFrame {
        let spectrum = fft.forward(vDSP.multiply(x, window)[...])
        let fullScale = vDSP.sum(window) / 2
        var db = bins.map { k -> Float in
            let magnitude = (spectrum.re[k] * spectrum.re[k] + spectrum.im[k] * spectrum.im[k]).squareRoot() / fullScale
            return 20 * log10(max(magnitude, 1e-9))
        }
        if let previous = s.previous {
            db = zip(previous, db).map { options.smoothing * $0 + (1 - options.smoothing) * $1 }
        }
        s.previous = db
        let time = Double(s.produced * options.hopSamples) / Double(SpeechDetector.sampleRate)
        return SpectrumFrame(timestamp: time, magnitudes: db, firstBinIndex: bins.lowerBound,
                             binHz: Float(SpeechDetector.sampleRate) / Float(options.fftSize))
    }
}
