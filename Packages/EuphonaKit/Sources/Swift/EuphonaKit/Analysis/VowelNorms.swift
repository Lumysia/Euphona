import Foundation

/// Average F1 and F2 of English vowels spoken by adult men and women, from Hillenbrand, Getty,
/// Clark & Wheeler (1995), "Acoustic characteristics of American English vowels", JASA 97(5).
/// The resonance chart draws them as landmarks: the same vowel sits further up and to the left
/// (higher F1 and F2) in a brighter, shorter vocal tract.
public enum VowelNorms {
    public struct Vowel: Sendable, Identifiable {
        /// IPA symbol.
        public var symbol: String
        public var masculine: Formants
        public var feminine: Formants
        public var id: String { symbol }
    }

    public static let vowels: [Vowel] = [
        Vowel(symbol: "i", masculine: Formants(f1: 342, f2: 2322), feminine: Formants(f1: 437, f2: 2761)),
        Vowel(symbol: "ɛ", masculine: Formants(f1: 580, f2: 1799), feminine: Formants(f1: 731, f2: 2058)),
        Vowel(symbol: "æ", masculine: Formants(f1: 588, f2: 1952), feminine: Formants(f1: 669, f2: 2349)),
        Vowel(symbol: "ɑ", masculine: Formants(f1: 768, f2: 1333), feminine: Formants(f1: 936, f2: 1551)),
        Vowel(symbol: "o", masculine: Formants(f1: 497, f2: 910), feminine: Formants(f1: 555, f2: 1035)),
        Vowel(symbol: "u", masculine: Formants(f1: 378, f2: 997), feminine: Formants(f1: 459, f2: 1105)),
    ]

    /// The chart's ranges, wide enough for every landmark and most live readings.
    public static let f1Range = 200.0...1_100.0
    public static let f2Range = 700.0...3_200.0
}

extension VowelNorms {
    /// Where a vowel sits between the darker (masculine) and brighter (feminine) form of the nearest
    /// landmark, measured on log frequencies: 0 at the masculine average, 100 at the feminine one.
    public static func brightness(_ formants: Formants) -> (vowel: Vowel, brightness: Double) {
        func point(_ f: Formants) -> (Double, Double) { (log(f.f1), log(f.f2)) }
        let p = point(formants)
        func distance(to vowel: Vowel) -> Double {
            let (m, f) = (point(vowel.masculine), point(vowel.feminine))
            let t = projection(p, m, f)
            let closest = (m.0 + (f.0 - m.0) * t, m.1 + (f.1 - m.1) * t)
            return hypot(p.0 - closest.0, p.1 - closest.1)
        }
        let vowel = vowels.min { distance(to: $0) < distance(to: $1) }!
        let t = projection(p, point(vowel.masculine), point(vowel.feminine))
        return (vowel, t * 100)
    }

    /// How far along the segment m→f the point's projection falls, clamped to 0...1.
    private static func projection(_ p: (Double, Double), _ m: (Double, Double), _ f: (Double, Double)) -> Double {
        let d = (f.0 - m.0, f.1 - m.1)
        let length = d.0 * d.0 + d.1 * d.1
        guard length > 0 else { return 0 }
        return min(max(((p.0 - m.0) * d.0 + (p.1 - m.1) * d.1) / length, 0), 1)
    }
}
