import Accelerate
import Foundation

/// Voice quality measures, the same algorithms as tools/voice-model/voice_quality.py:
/// HNR by normalized autocorrelation (Boersma 1993), jitter and shimmer from pitch-guided cycle peaks
/// (Praat's 1.3x and 1.6x neighbour limits), CPPS after Hillenbrand & Houde (1996), and intensity in dB
/// re 20 µPa with samples taken as pascals.
struct VoiceQuality: Sendable {
    static let window = 640
    static let minHz: Float = 75, maxHz: Float = 600, minConfidence: Float = 0.9
    private static let rate = Float(SpeechDetector.sampleRate)

    let samples: [Float]
    let segments: [Range<Int>]
    /// Voiced pitch per SwiftF0 frame, nil where unvoiced.
    let track: [Float?]

    init(samples: [Float], segments: [Range<Int>], pitch: PitchTrack) {
        self.samples = samples
        self.segments = segments
        track = pitch.voiced(minHz: Self.minHz, maxHz: Self.maxHz, minConfidence: Self.minConfidence)
    }

    private func inSpeech(_ position: Double) -> Bool {
        segments.contains { Double($0.lowerBound) <= position && position < Double($0.upperBound) }
    }

    private static func centre(_ frame: Int) -> Double { Double(frame * PitchTrack.hop) + PitchTrack.centreOffset }

    private static let hann: [Float] = (0..<window).map { 0.5 - 0.5 * cos(2 * .pi * Float($0 + 1) / Float(window + 1)) }

    // MARK: HNR

    struct HNRWindow { var range: Range<Int>; var db: Float? }

    func hnrWindows() -> [HNRWindow] {
        let fft = RealFFT(size: 2048)
        let windowR = autocorrelation(Self.hann, fft)
        let rw = vDSP.divide(windowR, windowR[0])
        let lo = Int((Self.rate / Self.maxHz).rounded(.up)), hi = Int(Self.rate / Self.minHz)
        var out: [HNRWindow] = []
        var start = 0
        while start + Self.window <= samples.count {
            let centre = start + Self.window / 2
            let frame = Int(((Double(centre) - PitchTrack.centreOffset) / Double(PitchTrack.hop)).rounded(.toNearestOrEven))
            var value: Float?
            if track.indices.contains(frame), track[frame] != nil, inSpeech(Double(centre)) {
                let slice = samples[start..<start + Self.window]
                let mean = vDSP.mean(slice)
                let x = vDSP.multiply(vDSP.add(-mean, slice), Self.hann)
                let r = autocorrelation(x, fft)
                if r[0] > 1e-12 {
                    var peak: Float = -.infinity
                    for lag in lo...hi { peak = max(peak, (r[lag] / r[0]) / max(rw[lag], 1e-6)) }
                    peak = min(max(peak, 1e-6), 1 - 1e-6)
                    value = 10 * log10(peak / (1 - peak))
                }
            }
            out.append(HNRWindow(range: start..<start + Self.window, db: value))
            start += Self.window
        }
        return out
    }

    /// The first `window` lags of the autocorrelation.
    private func autocorrelation(_ x: [Float], _ fft: RealFFT) -> [Float] {
        let spectrum = fft.forward(x[...])
        let power = zip(spectrum.re, spectrum.im).map { $0 * $0 + $1 * $1 }
        let r = fft.inverse(real: power)
        return Array(r.prefix(Self.window))
    }

    // MARK: Cycles

    private func cycles() -> [(periods: [Float], amplitudes: [Float])] {
        let centres = track.indices.map(Self.centre)
        let voiced = track.indices.map { track[$0] != nil && inSpeech(centres[$0]) }
        var runs: [(Int, Int)] = []
        var i = 0
        while i < track.count {
            guard voiced[i] else { i += 1; continue }
            var j = i
            while j + 1 < track.count, voiced[j + 1] { j += 1 }
            if j - i >= 2 { runs.append((i, j)) }
            i = j + 1
        }
        var result: [(periods: [Float], amplitudes: [Float])] = []
        for (a, b) in runs {
            let xs = Array(centres[a...b]), ys = (a...b).map { track[$0]! }
            func period(_ p: Int) -> Float { Self.rate / interpolate(Double(p), xs, ys) }
            let first = Int(centres[a]), last = min(Int(centres[b]), samples.count - 1)
            let t0 = Int(period(first))
            let segment = samples[first..<min(first + t0, samples.count)]
            guard segment.count >= 2, let top = segment.max(), let bottom = segment.min() else { continue }
            let sign: Float = top >= -bottom ? 1 : -1
            var p = first + argmax(segment, sign: sign)
            var periods: [Float] = [], amplitudes: [Float] = []
            while true {
                let t = period(p)
                let lo = p + Int(0.8 * t), hi = p + Int((1.2 * t).rounded(.up))
                if hi >= last { break }
                let q = lo + argmax(samples[lo...hi], sign: sign)
                periods.append(Float(q - p) / Self.rate)
                amplitudes.append(abs(samples[q]))
                p = q
            }
            if periods.count >= 3 { result.append((periods, amplitudes)) }
        }
        return result
    }

    private func argmax(_ x: ArraySlice<Float>, sign: Float) -> Int {
        var best = x.startIndex
        for i in x.indices where sign * x[i] > sign * x[best] { best = i }
        return best - x.startIndex
    }

    /// np.interp: linear between points, held at the ends.
    private func interpolate(_ x: Double, _ xs: [Double], _ ys: [Float]) -> Float {
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var k = 1
        while xs[k] < x { k += 1 }
        let t = Float((x - xs[k - 1]) / (xs[k] - xs[k - 1]))
        return ys[k - 1] + (ys[k] - ys[k - 1]) * t
    }

    /// Local, 3-point and 5-point relative perturbation, pooled over runs.
    static func perturbation(_ series: [[Float]], factor: Float) -> (local: Float, three: Float, five: Float) {
        var local: [Float] = [], three: [Float] = [], five: [Float] = [], all: [Float] = []
        for x in series {
            for i in 1..<x.count where max(x[i], x[i - 1]) / max(min(x[i], x[i - 1]), 1e-12) <= factor {
                local.append(abs(x[i] - x[i - 1]))
            }
            if x.count >= 3 { for i in 1..<x.count - 1 { three.append(abs(x[i] - (x[i - 1] + x[i] + x[i + 1]) / 3)) } }
            if x.count >= 5 { for i in 2..<x.count - 2 { five.append(abs(x[i] - x[i - 2...i + 2].reduce(0, +) / 5)) } }
            all += x
        }
        let mean = all.isEmpty ? Float.nan : vDSP.mean(all)
        func relative(_ v: [Float]) -> Float { !v.isEmpty && mean > 0 ? vDSP.mean(v) / mean : .nan }
        return (relative(local), relative(three), relative(five))
    }

    // MARK: CPPS

    func cpps() -> Float {
        let n = 1024, hop = 160
        let fft = RealFFT(size: n)
        var rows: [[Float]] = []
        for segment in segments {
            var start = segment.lowerBound
            while start + Self.window <= segment.upperBound, start + Self.window <= samples.count {
                let x = vDSP.multiply(samples[start..<start + Self.window], Self.hann)
                let s = fft.forward(x[...])
                let db = zip(s.re, s.im).map { 10 * log10($0 * $0 + $1 * $1 + 1e-12) }
                let c = fft.inverse(real: db)
                rows.append(c.prefix(n / 2).map { 20 * log10(abs($0) + 1e-12) })
                start += hop
            }
        }
        guard rows.count >= 7 else { return .nan }
        let width = n / 2
        let timeSmoothed: [[Float]] = rows.indices.map { i in
            let block = rows[max(0, i - 3)..<min(rows.count, i + 4)]
            var sum = [Float](repeating: 0, count: width)
            for r in block { vDSP.add(sum, r, result: &sum) }
            return vDSP.divide(sum, Float(block.count))
        }
        let lo = Int((Self.rate / 600).rounded(.up)), hi = Int(Self.rate / 60)
        let fitStart = SpeechDetector.sampleRate / 1000
        var values: [Float] = []
        for row in timeSmoothed {
            let r: [Float] = (0..<width).map { k in
                var sum: Float = 0
                for d in -1...1 where (0..<width).contains(k + d) { sum += row[k + d] }
                return sum / 3
            }
            // Least-squares line over quefrency bins from 1 ms.
            let qs = (fitStart..<width).map(Double.init), vs = r[fitStart...].map(Double.init)
            let qm = qs.reduce(0, +) / Double(qs.count), vm = vs.reduce(0, +) / Double(vs.count)
            var sxy = 0.0, sxx = 0.0
            for (q, v) in zip(qs, vs) { sxy += (q - qm) * (v - vm); sxx += (q - qm) * (q - qm) }
            let slope = sxy / sxx, intercept = vm - slope * qm
            var k = lo
            for j in lo...hi where r[j] > r[k] { k = j }
            values.append(r[k] - Float(slope * Double(k) + intercept))
        }
        return vDSP.mean(values)
    }

    // MARK: All measures

    func features() -> VoiceQualityFeatures {
        let speechFrames = track.indices.filter { inSpeech(Self.centre($0)) }
        let voiced = speechFrames.compactMap { track[$0] }
        let hnr = hnrWindows().compactMap(\.db)
        let cyc = cycles()
        let jitter = Self.perturbation(cyc.map(\.periods), factor: 1.3)
        let shimmer = Self.perturbation(cyc.map(\.amplitudes), factor: 1.6)
        var intensity: [Float] = []
        for segment in segments {
            var s = segment.lowerBound
            while s + 160 <= segment.upperBound, s + 160 <= samples.count {
                let power = vDSP.sumOfSquares(samples[s..<s + 160]) / 160
                if power > 0 { intensity.append(10 * log10(power / 4e-10)) }
                s += 160
            }
        }
        func q(_ v: [Float], _ p: Float) -> Double { v.isEmpty ? .nan : Double(Stats.percentile(v, p)) }
        return VoiceQualityFeatures(
            hnrDb: hnr.isEmpty ? .nan : Double(vDSP.mean(hnr)),
            cppsDb: Double(cpps()),
            jitterLocal: Double(jitter.local), jitterRap: Double(jitter.three), jitterPpq5: Double(jitter.five),
            shimmerLocal: Double(shimmer.local), shimmerApq3: Double(shimmer.three), shimmerApq5: Double(shimmer.five),
            f0Median: q(voiced, 50), f0Iqr: q(voiced, 75) - q(voiced, 25),
            f0Cv: voiced.isEmpty ? .nan : Double(Stats.std(voiced) / vDSP.mean(voiced)),
            voicedFraction: Double(voiced.count) / Double(max(speechFrames.count, 1)),
            intensityMedian: q(intensity, 50), intensityIqr: q(intensity, 75) - q(intensity, 25)
        )
    }
}
