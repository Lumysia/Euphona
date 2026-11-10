import Foundation
import Testing
@testable import EuphonaKit

struct AnalysisLogicTests {
    @Test func trackerCountsOverlapsOnce() {
        var tracker = SpeechIntervalTracker()
        tracker.add(SpeechInterval(start: 0, end: 1))
        tracker.add(SpeechInterval(start: 0.5, end: 1.5))
        tracker.add(SpeechInterval(start: 1.5005, end: 2))
        tracker.add(SpeechInterval(start: 3, end: 2.5))
        #expect(abs(tracker.totalSeconds - 2) < 1e-9)
    }

    @Test func liveCounterEmitsAWindowEvery300ms() {
        var counter = LiveSpeechCounter()
        let windows = counter.append([Float](repeating: 0, count: 16_000 * 2))
        #expect(windows.count == 2 * 16_000 / LiveSpeechCounter.stepSamples)
        let last = try! #require(windows.last)
        #expect(last.samples.count == LiveSpeechCounter.windowSamples)
        #expect(last.startSample + last.samples.count == windows.count * LiveSpeechCounter.stepSamples)
    }

    @Test func liveCounterPlacesSegmentsOnTheRecordingTimeline() {
        var counter = LiveSpeechCounter()
        let windows = counter.append([Float](repeating: 0, count: 16_000 * 3))
        for window in windows { counter.record([SpeechInterval(start: 0, end: 0.9)], in: window) }
        #expect(abs(counter.speechSeconds - (Double(windows.last!.startSample) / 16_000 + 0.9)) < 1e-6)
    }

    @Test func timelineOnlyScoresSpeech() throws {
        let result = sampleResult
        let timeline = ScoreTimeline(result: result, duration: 6)
        #expect(timeline.point(at: 0.1) == nil)
        let point = try #require(timeline.point(at: 1.0))
        #expect(point.timbreScore == 60)
        #expect(timeline.point(at: 3.0) == nil)
    }

    @Test func segmentScoresUseScoringRules() throws {
        let result = sampleResult
        let scores = SegmentScore.segments(of: result)
        #expect(scores.count == 1)
        // The segment's speaking pitch is the median of its voiced windows (180, 184, 260).
        let expected = EuphonaAnalyzer.score(profile: .feminization, timbreScore: 60, flow: 85, ease: 90, f0Hz: 184)
        #expect(scores[0].score == expected.finalScore)
    }

    @Test func waveformTakesPeaksPerBucket() {
        let audio = PCMBuffer(samples: [0.1, -0.5, 0.2, 0.9], sampleRate: 16_000)
        #expect(Waveform.peaks(of: audio, buckets: 2) == [0.5, 0.9])
    }
}

struct PitchChartTests {
    @Test func ticksFollowTheSpanAndIncludeTheMidpoint() {
        #expect(PitchChartMath.ticks(min: 75, max: 350) == [100, 153, 200, 300])
        #expect(PitchChartMath.ticks(min: 100, max: 200) == [100, 120, 140, 153, 160, 180, 200])
    }

    @Test func splineNeverRunsBackwardsInTime() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 10), CGPoint(x: 1.1, y: -5), CGPoint(x: 3, y: 2)]
        for segment in PitchChartMath.bSpline(points) {
            let low = min(segment.start.x, segment.end.x), high = max(segment.start.x, segment.end.x)
            #expect((low...high).contains(segment.control1.x) && (low...high).contains(segment.control2.x))
        }
    }

    @Test func hopFollowsTheOutputRate() {
        #expect(RealtimeF0Stream.hopSamples(forOutputRate: 30) == 533)
        #expect(RealtimeF0Stream.hopSamples(forOutputRate: 120) == 256)
    }
}
