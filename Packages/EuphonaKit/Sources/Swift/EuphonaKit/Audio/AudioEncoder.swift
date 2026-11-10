import AVFAudio
import Foundation

/// Encodes recordings to AAC for history, so iCloud stores about a quarter of the WAV size.
/// Analysis always runs on the original PCM.
public enum AudioEncoder {
    public static let fileExtension = "m4a"

    public static func aac(_ audio: PCMBuffer) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: audio.channels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(audio.sampleRate),
                                         channels: AVAudioChannelCount(audio.channels), interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(audio.samples.count / audio.channels))
        else { throw AudioFileReader.Unreadable() }
        buffer.frameLength = buffer.frameCapacity
        audio.samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: source.count)
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: true)
            try file.write(from: buffer)
        }
        return try Data(contentsOf: url)
    }
}
