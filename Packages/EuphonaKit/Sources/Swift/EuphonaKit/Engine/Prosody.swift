import Accelerate
import Foundation

/// The loudness envelope and its syllable peaks, as tools/voice-model/prosody.py computes them, for
/// the articulation rate in `SpeechFlow`.
enum Prosody {
    static let envelopeHop = 160

    /// Syllable nuclei: envelope peaks within 25 dB of the loudest, 60 ms apart, 3 dB prominent.
    static func syllables(_ envelope: [Float]) -> Int {
        guard envelope.count > 5, let top = envelope.max() else { return 0 }
        return Peaks.find(envelope, minHeight: top - 25, minDistance: 6, minProminence: 3).count
    }

    /// Loudness in dB per 10 ms over the speech segments joined, smoothed over 50 ms.
    static func envelope(_ samples: [Float], _ segments: [Range<Int>]) -> [Float] {
        let speech = segments.flatMap { samples[$0.clamped(to: 0..<samples.count)] }
        let frames = speech.count / envelopeHop
        guard frames > 0 else { return [] }
        let db: [Float] = (0..<frames).map { f in
            let slice = speech[f * envelopeHop..<(f + 1) * envelopeHop]
            let power = vDSP.sumOfSquares(slice) / Float(envelopeHop)
            return 10 * log10(power + 1e-10)
        }
        // A centred 5-frame mean with zeros beyond the ends (numpy's convolve "same").
        return db.indices.map { i in
            var sum: Float = 0
            for k in -2...2 where db.indices.contains(i + k) { sum += db[i + k] }
            return sum / 5
        }
    }
}

/// Peak picking with SciPy's `find_peaks` semantics for height, distance and prominence.
enum Peaks {
    static func find(_ x: [Float], minHeight: Float, minDistance: Int, minProminence: Float) -> [Int] {
        var peaks: [Int] = []
        var i = 1
        while i < x.count - 1 {
            if x[i - 1] < x[i] {
                var ahead = i + 1
                while ahead < x.count - 1, x[ahead] == x[i] { ahead += 1 }
                if x[ahead] < x[i] {
                    peaks.append((i + ahead - 1) / 2)
                    i = ahead
                }
            }
            i += 1
        }
        peaks = peaks.filter { x[$0] >= minHeight }
        // Keep the highest peaks first, dropping lower ones closer than the distance.
        var keep = [Bool](repeating: true, count: peaks.count)
        let order = peaks.indices.sorted { (x[peaks[$0]], $0) < (x[peaks[$1]], $1) }
        for j in order.reversed() where keep[j] {
            var k = j - 1
            while k >= 0, peaks[j] - peaks[k] < minDistance { keep[k] = false; k -= 1 }
            k = j + 1
            while k < peaks.count, peaks[k] - peaks[j] < minDistance { keep[k] = false; k += 1 }
        }
        peaks = peaks.indices.filter { keep[$0] }.map { peaks[$0] }
        return peaks.filter { prominence(x, $0) >= minProminence }
    }

    static func prominence(_ x: [Float], _ peak: Int) -> Float {
        var leftMin = x[peak], i = peak
        while i >= 0, x[i] <= x[peak] { leftMin = min(leftMin, x[i]); i -= 1 }
        var rightMin = x[peak]
        i = peak
        while i < x.count, x[i] <= x[peak] { rightMin = min(rightMin, x[i]); i += 1 }
        return x[peak] - max(leftMin, rightMin)
    }
}

/// NumPy-compatible statistics.
enum Stats {
    static func median(_ v: [Float]) -> Float { percentile(v, 50) }

    /// Linear interpolation between closest ranks, as numpy.percentile.
    static func percentile(_ v: [Float], _ q: Float) -> Float {
        guard !v.isEmpty else { return .nan }
        let sorted = v.sorted()
        let position = Float(sorted.count - 1) * q / 100
        let low = Int(position.rounded(.down)), high = min(low + 1, sorted.count - 1)
        return sorted[low] + (sorted[high] - sorted[low]) * (position - Float(low))
    }

    /// Population standard deviation.
    static func std(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return .nan }
        let mean = vDSP.mean(v)
        return (v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(v.count)).squareRoot()
    }
}
