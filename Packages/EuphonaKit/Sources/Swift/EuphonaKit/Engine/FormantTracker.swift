import Foundation
import Synchronization

/// The first formants of one voiced frame, in Hz.
public struct Formants: Sendable, Equatable {
    public var f1: Double
    public var f2: Double
    public var f3: Double?

    public init(f1: Double, f2: Double, f3: Double? = nil) {
        self.f1 = f1
        self.f2 = f2
        self.f3 = f3
    }
}

/// Formants by linear prediction: pre-emphasis, a Hamming window, autocorrelation and Levinson–Durbin,
/// then the resonance peaks of the LPC envelope with their −3 dB bandwidths. A peak counts as a
/// formant only when it is narrow enough to be a resonance rather than a slope.
struct FormantTracker: Sendable {
    static let sampleRate = 16_000.0
    /// 32 ms: long enough to hold a few periods of a low voice.
    static let frameLength = 512
    static let order = 16
    /// Envelope resolution, 0–5 kHz.
    static let gridPoints = 1_000
    static let ceilingHz = 5_000.0
    static let maximumBandwidthHz = 500.0
    static let f1Range = 200.0...1_100.0
    static let f2Range = 600.0...3_200.0
    static let f3Range = 1_500.0...4_200.0

    private let window: [Double] = (0..<frameLength).map { 0.54 - 0.46 * cos(2 * .pi * Double($0) / Double(frameLength - 1)) }
    /// Pre-emphasis from about 50 Hz, flattening the voice's spectral tilt.
    private let emphasis = exp(-2 * .pi * 50 / sampleRate)

    func formants(_ frame: ArraySlice<Float>) -> Formants? {
        guard frame.count == Self.frameLength else { return nil }
        var x = [Double](repeating: 0, count: Self.frameLength)
        var previous = Double(frame.first ?? 0)
        for (i, sample) in frame.enumerated() {
            let value = Double(sample)
            x[i] = (value - emphasis * previous) * window[i]
            previous = value
        }
        guard let lpc = Self.predictor(x) else { return nil }
        let peaks = Self.peaks(lpc)
        guard let f1 = peaks.first(where: { Self.f1Range.contains($0) }),
              let f2 = peaks.first(where: { Self.f2Range.contains($0) && $0 > f1 + 150 })
        else { return nil }
        return Formants(f1: f1, f2: f2, f3: peaks.first { Self.f3Range.contains($0) && $0 > f2 + 150 })
    }

    /// LPC coefficients a[0...order] with a[0] = 1, or nil for a silent or unstable frame.
    static func predictor(_ x: [Double]) -> [Double]? {
        var r = [Double](repeating: 0, count: order + 1)
        for lag in 0...order {
            var sum = 0.0
            for i in lag..<x.count { sum += x[i] * x[i - lag] }
            r[lag] = sum
        }
        guard r[0] > 1e-10 else { return nil }
        r[0] *= 1 + 1e-9
        var a = [Double](repeating: 0, count: order + 1)
        a[0] = 1
        var error = r[0]
        for i in 1...order {
            var acc = r[i]
            for j in 1..<i { acc += a[j] * r[i - j] }
            let k = -acc / error
            guard abs(k) < 1 else { return nil }
            let previous = a
            for j in 1..<i { a[j] = previous[j] + k * previous[i - j] }
            a[i] = k
            error *= 1 - k * k
        }
        return a
    }

    /// Frequencies of the envelope's narrow peaks, ascending, refined by parabolic interpolation.
    static func peaks(_ a: [Double]) -> [Double] {
        let step = ceilingHz / Double(gridPoints - 1)
        let power: [Double] = (0..<gridPoints).map { index in
            let w = 2 * .pi * Double(index) * step / sampleRate
            var re = 0.0, im = 0.0
            for (k, c) in a.enumerated() {
                re += c * cos(w * Double(k))
                im -= c * sin(w * Double(k))
            }
            return 1 / max(re * re + im * im, 1e-20)
        }
        var found: [Double] = []
        for i in 1..<(gridPoints - 1) where power[i] > power[i - 1] && power[i] >= power[i + 1] {
            let half = power[i] / 2
            guard let left = (0..<i).reversed().first(where: { power[$0] < half }),
                  let right = ((i + 1)..<gridPoints).first(where: { power[$0] < half }),
                  Double(right - left) * step <= maximumBandwidthHz
            else { continue }
            let (l, c, r) = (log(power[i - 1]), log(power[i]), log(power[i + 1]))
            let denominator = l - 2 * c + r
            let offset = denominator == 0 ? 0 : 0.5 * (l - r) / denominator
            found.append((Double(i) + offset) * step)
        }
        return found
    }
}

public struct FormantFrame: Sendable, Equatable {
    public var timestamp: Double
    public var formants: Formants
}

/// Live formants: one frame every 32 ms, emitted only for loud, periodic (voiced) frames.
public final class RealtimeFormantStream: Sendable {
    public static let sampleRate = Int(FormantTracker.sampleRate)
    static let hop = FormantTracker.frameLength
    /// Quietest frame looked at, as RMS.
    static let minimumLevel: Float = 0.003
    /// Normalized autocorrelation a voiced frame reaches at its period (70–800 Hz).
    static let minimumPeriodicity = 0.45

    private struct State {
        var buffer: [Float] = []
        var consumed = 0
    }

    private let tracker = FormantTracker()
    private let state = Mutex(State())

    public init() {}

    public func process(_ samples: [Float]) -> [FormantFrame] {
        let frames: [(ArraySlice<Float>, Int)] = state.withLock { s in
            s.buffer += samples
            var out: [(ArraySlice<Float>, Int)] = []
            var start = 0
            while s.buffer.count - start >= FormantTracker.frameLength {
                out.append((s.buffer[start..<start + FormantTracker.frameLength], s.consumed + start + FormantTracker.frameLength))
                start += Self.hop
            }
            s.buffer.removeFirst(start)
            s.consumed += start
            return out
        }
        return frames.compactMap { frame, end in
            guard Self.isVoiced(frame), let formants = tracker.formants(frame) else { return nil }
            return FormantFrame(timestamp: Double(end) / FormantTracker.sampleRate, formants: formants)
        }
    }

    public func reset() {
        state.withLock { $0 = State() }
    }

    static func isVoiced(_ frame: ArraySlice<Float>) -> Bool {
        let x = Array(frame)
        let energy = x.reduce(0) { $0 + Double($1) * Double($1) }
        guard sqrt(energy / Double(x.count)) >= Double(minimumLevel) else { return false }
        let lags = Int(FormantTracker.sampleRate / 800)...Int(FormantTracker.sampleRate / 70)
        var best = 0.0
        for lag in lags {
            var sum = 0.0, a = 0.0, b = 0.0
            for i in lag..<x.count {
                sum += Double(x[i]) * Double(x[i - lag])
                a += Double(x[i]) * Double(x[i])
                b += Double(x[i - lag]) * Double(x[i - lag])
            }
            best = max(best, sum / max(sqrt(a * b), 1e-12))
        }
        return best >= minimumPeriodicity
    }
}
