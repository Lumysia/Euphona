import AVFAudio
import Foundation
import NaturalLanguage
import EuphonaKit
import Speech

/// What was said in a recording, from the system's on-device speech-to-text, and how fast.
struct Transcript: Equatable {
    var text: String
    var wordsPerMinute: Double?

    /// Transcribes in the app's language, downloading the system's speech model for it once.
    /// Nil when the language has no transcriber or anything fails: the lesson works without it.
    static func of(_ audio: PCMBuffer, speechSeconds: Double) async -> Transcript? {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: url) }
            try write(audio, to: url)
            let file = try AVAudioFile(forReading: url)
            async let text = transcriber.results.reduce(into: "") { $0 += String($1.text.characters) }
            _ = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
            let spoken = try await text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty else { return nil }
            return Transcript(text: spoken, wordsPerMinute: rate(spoken, seconds: speechSeconds, locale: locale))
        } catch {
            return nil
        }
    }

    /// Words per minute of speech, counting words the way the language divides them.
    private static func rate(_ text: String, seconds: Double, locale: Locale) -> Double? {
        guard seconds >= 5 else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        if let code = locale.language.languageCode?.identifier { tokenizer.setLanguage(NLLanguage(code)) }
        let words = tokenizer.tokens(for: text.startIndex..<text.endIndex).count
        return Double(words) / seconds * 60
    }

    private static func write(_ audio: PCMBuffer, to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate), channels: AVAudioChannelCount(audio.channels)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count / max(audio.channels, 1)))
        else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = buffer.frameCapacity
        // Interleaved samples into the buffer's separate channels.
        for channel in 0..<audio.channels {
            let destination = buffer.floatChannelData![channel]
            for frame in 0..<Int(buffer.frameLength) { destination[frame] = audio.samples[frame * audio.channels + channel] }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
