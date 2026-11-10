import Testing
@testable import EuphonaKit

struct PitchBalanceTests {
    static func frames(_ hz: Float, from start: Double, seconds: Double) -> [F0Frame] {
        stride(from: start, to: start + seconds, by: 1.0 / 30).map { F0Frame(timestamp: $0, f0Hz: hz, confidence: 0.9, voiced: true) }
    }

    @Test func mapsSemitonesLikeTheScore() {
        #expect(abs(PitchBalance.balance(hz: Scoring.pitchMidpointHz) - 0.5) < 1e-9)
        #expect(PitchBalance.balance(hz: 300) == 1)
        #expect(PitchBalance.balance(hz: 90) == 0)
        #expect(PitchBalance.balance(hz: 196) > 0.5 && PitchBalance.balance(hz: 140) < 0.5)
    }

    @Test func followsTheVoiceThenRelaxesToRest() {
        var balance = PitchBalance()
        #expect(balance.balance(at: 0, resting: 0.3) == 0.3)
        balance.ingest(Self.frames(220, from: 0, seconds: 1))
        let speaking = balance.balance(at: 1, resting: 0.3)
        #expect(abs(speaking - PitchBalance.balance(hz: 220)) < 0.01)
        #expect(balance.balance(at: 1.5, resting: 0.3) == speaking)
        let relaxing = balance.balance(at: 2.3, resting: 0.3)
        #expect(relaxing < speaking && relaxing > 0.3)
        #expect(abs(balance.balance(at: 10, resting: 0.3) - 0.3) < 1e-9)
    }

    @Test func smoothsAStrayFrame() {
        var balance = PitchBalance()
        balance.ingest(Self.frames(220, from: 0, seconds: 1))
        balance.ingest([F0Frame(timestamp: 1, f0Hz: 110, confidence: 0.9, voiced: true)])
        #expect(balance.balance(at: 1, resting: 0.5) > PitchBalance.balance(hz: 190))
    }

    @Test func ignoresUnvoicedFrames() {
        var balance = PitchBalance()
        balance.ingest([F0Frame(timestamp: 0, f0Hz: 300, confidence: 0.1, voiced: false)])
        #expect(balance.balance(at: 0, resting: 0.4) == 0.4)
    }
}

struct PitchTargetTests {
    @Test func bandIsFixed() {
        let band = PitchTarget.typicalBand(for: .feminine)
        #expect(band.contains(200, at: 0) && band.contains(200, at: 99))
        #expect(!band.contains(150, at: 0))
    }

    @Test func glideRisesAndFallsInSemitones() {
        let glide = PitchTarget.glide(low: 110, high: 440, period: 4, toleranceSemitones: 1)
        func center(_ t: Double) -> Double { let r = glide.range(at: t); return (r.lowerBound * r.upperBound).squareRoot() }
        #expect(abs(center(0) - 110) < 0.01)
        #expect(abs(center(1) - 220) < 0.01)
        #expect(abs(center(2) - 440) < 0.01)
        #expect(abs(center(3) - 220) < 0.01)
        #expect(abs(center(4) - 110) < 0.01)
        #expect(glide.contains(225, at: 1) && !glide.contains(260, at: 1))
    }

    @Test func shareCountsSamplesOnTarget() {
        let band = PitchTarget.band(low: 100, high: 200)
        #expect(PitchTarget.share([(0, 150), (1, 250), (2, 190), (3, 90)], on: band) == 0.5)
        #expect(PitchTarget.share([], on: band) == nil)
    }
}
