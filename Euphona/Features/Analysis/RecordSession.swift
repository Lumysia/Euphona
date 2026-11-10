import Foundation
import Observation
import EuphonaKit
import SwiftData

/// What a finished analysis shows.
struct AnalysisOutcome {
    var result: EuphonaResult
    var recordID: PersistentIdentifier?
    var audio: PCMBuffer
    /// The AAC encoding kept in history, for playback.
    var audioData: Data?
    var waveform: [Float]
    var timeline: ScoreTimeline
    var segmentScores: [SegmentScore]
    var previousScore: Double?
    var previousMetrics: PreviousMetrics?
    var previousRecording: PreviousRecording?
}

/// The recording a result is compared with, for listening back.
struct PreviousRecording {
    var audio: Data
    var date: Date
    var duration: Double

    init?(_ record: AnalysisRecord?) {
        guard let record, let audio = record.audio else { return nil }
        self.audio = audio
        date = record.date
        duration = record.inputSeconds
    }
}

/// The metrics of the analysis before this one, for comparison.
struct PreviousMetrics: Hashable {
    var timbreScore: Double
    var flowScore: Double
    var easeScore: Double
    var speakingF0Hz: Double?

    init(_ record: AnalysisRecord) {
        timbreScore = record.timbreScore
        flowScore = record.flowScore
        easeScore = record.easeScore
        speakingF0Hz = record.speakingF0Hz
    }
}

/// Records, analyzes and saves a voice analysis.
@MainActor @Observable
final class RecordSession {
    static let maximumSeconds = 60.0
    static let minimumSeconds = 5.0
    static let minimumSpeechSeconds = 5.0

    enum State {
        case ready, recording, analyzing(AnalysisProgress?), finished(AnalysisOutcome)
        case failed(CaptureFailure)
    }

    /// What a recording needs from the app.
    struct Dependencies {
        var engine: VoiceEngine
        var settings: AppSettings
        var context: ModelContext
        var errors: ErrorCenter
    }

    private(set) var state: State = .ready
    let capture = SpeechCapture(maximumSeconds: maximumSeconds, mode: .voice)
    @ObservationIgnored private var dependencies: Dependencies?
    /// Bumped by `cancel()`, so an analysis still running when the page closes is dropped, not saved.
    @ObservationIgnored private var generation = 0

    var isBusy: Bool {
        switch state {
        case .recording, .analyzing: true
        default: false
        }
    }

    func start(_ dependencies: Dependencies) async {
        guard !isBusy else { return }
        self.dependencies = dependencies
        guard await MicrophoneCapture.requestPermission() else {
            state = .failed(.microphoneDenied)
            return
        }
        do {
            let analyzer = try await dependencies.engine.analyzer(for: dependencies.settings.analyzer)
            try capture.start(analyzer: analyzer) { [weak self] in Task { await self?.stop() } }
            state = .recording
        } catch {
            state = .failed(.couldNotStart)
        }
    }

    func stop() async {
        guard case .recording = state, let dependencies else { return }
        state = .analyzing(nil)
        let generation = generation
        let audio = await capture.stop()
        guard generation == self.generation else { return }
        guard audio.duration >= Self.minimumSeconds, capture.speechSeconds >= Self.minimumSpeechSeconds else {
            state = .failed(.tooLittleSpeech)
            return
        }
        await analyze(audio, dependencies)
    }

    /// Analyzes the start of an audio or video file (up to `maximumSeconds`) the way a recording is
    /// analyzed and saved.
    func analyze(file url: URL, _ dependencies: Dependencies) async {
        guard !isBusy else { return }
        self.dependencies = dependencies
        state = .analyzing(nil)
        let generation = generation
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let audio = try? await AudioFileReader.read(url, maximumSeconds: Self.maximumSeconds) else {
            if generation == self.generation { state = .failed(.unreadableFile) }
            return
        }
        guard generation == self.generation else { return }
        guard audio.duration >= Self.minimumSeconds else {
            state = .failed(.tooLittleSpeech)
            return
        }
        await analyze(audio, dependencies)
    }

    /// Abandons a recording or an analysis in progress; nothing is saved.
    func cancel() async {
        generation += 1
        if case .recording = state { _ = await capture.stop() }
        state = .ready
    }

    func reset() {
        guard !isBusy else { return }
        state = .ready
    }

    private func analyze(_ audio: PCMBuffer, _ dependencies: Dependencies) async {
        let profile = dependencies.settings.voiceGoal.scoreProfile
        let generation = generation
        do {
            let analyzer = try await dependencies.engine.analyzer(for: dependencies.settings.analyzer)
            let result = try await offMain {
                try analyzer.analyze(audio, profile: profile) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .analyzing = self.state else { return }
                        self.state = .analyzing(progress)
                    }
                }
            }
            guard generation == self.generation else { return }
            // A recording is checked while it runs; a file only here.
            guard result.speech.seconds >= Self.minimumSpeechSeconds else {
                state = .failed(.tooLittleSpeech)
                return
            }
            let encoded = try? await offMain { try AudioEncoder.aac(audio) }
            guard generation == self.generation else { return }
            let store = HistoryStore(context: dependencies.context)
            let previous = try? store.previousAnalysis(before: .now, profile: profile)
            var saved: AnalysisRecord?
            do {
                saved = try store.addAnalysis(result, audio: encoded, audioFormat: encoded == nil ? nil : AudioEncoder.fileExtension)
            } catch {
                dependencies.errors.report(.errorSaveFailed, message: .errorSaveFailedMessage)
            }
            state = .finished(AnalysisOutcome(
                result: result,
                recordID: saved?.persistentModelID,
                audio: audio,
                audioData: encoded,
                waveform: Waveform.peaks(of: audio),
                timeline: ScoreTimeline(result: result, duration: audio.duration),
                segmentScores: SegmentScore.segments(of: result),
                previousScore: previous?.finalScore,
                previousMetrics: previous.map(PreviousMetrics.init),
                previousRecording: PreviousRecording(previous)
            ))
        } catch let error as AnalysisError where error.kind == .noSpeech {
            guard generation == self.generation else { return }
            state = .failed(.tooLittleSpeech)
        } catch {
            guard generation == self.generation else { return }
            state = .failed(.analysisFailed)
        }
    }
}
