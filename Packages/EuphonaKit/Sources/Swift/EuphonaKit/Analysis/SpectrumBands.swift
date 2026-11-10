import Foundation

/// Spectrogram math: 256 log-spaced bands (band 0 is the highest frequency), the
/// peak per band, and a dB-to-color ramp.
public enum SpectrumBands {
    public static let count = 256
    public static let floorDb: Float = -90
    public static let rangeDb: Float = 75

    public static func bands(of frame: SpectrumFrame) -> [Float] {
        let magnitudes = frame.magnitudes
        guard !magnitudes.isEmpty, frame.binHz > 0 else { return Array(repeating: floorDb, count: count) }
        let first = Double(frame.firstBinIndex)
        let minHz = max(first * Double(frame.binHz), 1)
        let maxHz = (first + Double(magnitudes.count - 1)) * Double(frame.binHz)
        let logRange = log(maxHz / minHz)
        func bin(_ ratio: Double) -> Int {
            let index = Int((minHz * exp(ratio * logRange) / Double(frame.binHz) - first).rounded())
            return min(max(index, 0), magnitudes.count - 1)
        }
        return (0..<count).map { band in
            let low = bin(1 - Double(band + 1) / Double(count))
            let high = max(bin(1 - Double(band) / Double(count)), low)
            let peak = magnitudes[low...high].max() ?? floorDb
            return peak.isFinite ? peak : magnitudes[high]
        }
    }

    /// 0…1 position of a dB value on the color ramp.
    public static func level(_ db: Float) -> Float { min(max((db - floorDb) / rangeDb, 0), 1) }

    /// RGB for a level: night → blue → cyan → pink → warm white (stops at 0.28, 0.50, 0.68).
    public static func color(_ level: Float) -> (UInt8, UInt8, UInt8) {
        let stops: [(Float, UInt32)] = [(0, 0x111827), (0.28, 0x2357D8), (0.50, 0x19B9C8), (0.68, 0xE75480), (1, 0xFFD9A0)]
        let upper = stops.firstIndex { $0.0 >= level } ?? stops.count - 1
        let lower = max(upper - 1, 0)
        let span = stops[upper].0 - stops[lower].0
        let t = span > 0 ? (level - stops[lower].0) / span : 0
        func channel(_ shift: UInt32) -> UInt8 {
            let a = Float((stops[lower].1 >> shift) & 0xFF), b = Float((stops[upper].1 >> shift) & 0xFF)
            return UInt8((a + (b - a) * t).rounded())
        }
        return (channel(16), channel(8), channel(0))
    }
}
