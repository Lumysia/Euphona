import AVFoundation

public enum AudioFileReader {
    public struct Unreadable: Error {}

    /// Reads the sound of any file AVFoundation opens, audio or video, as mono float PCM at the
    /// file's own rate; the analyzer resamples to 16 kHz itself. `maximumSeconds` keeps only the
    /// start of a long file.
    public static func read(_ url: URL, maximumSeconds: Double? = nil) async throws -> PCMBuffer {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Unreadable() }
        let description = try await track.load(.formatDescriptions).first
        let rate = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 44_100
        // Decoding blocks its thread until each buffer is ready, so it runs on a dispatch queue rather
        // than holding one of Swift concurrency's few threads; with all of those blocked in readers
        // at once (a few parallel reads on a small machine), decoding never finished.
        // The track only describes the file; after this it is used on the decoding queue alone.
        nonisolated(unsafe) let decodedTrack = track
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try decode(asset, track: decodedTrack, rate: rate, maximumSeconds: maximumSeconds) })
            }
        }
    }

    private static func decode(_ asset: AVURLAsset, track: AVAssetTrack, rate: Double, maximumSeconds: Double?) throws -> PCMBuffer {
        let reader = try AVAssetReader(asset: asset)
        if let maximumSeconds {
            reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: maximumSeconds, preferredTimescale: 600))
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: rate,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Unreadable() }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &chunk) == kCMBlockBufferNoErr
            else { throw Unreadable() }
            samples += chunk
        }
        guard reader.status == .completed, !samples.isEmpty else { throw reader.error ?? Unreadable() }
        return PCMBuffer(samples: samples, sampleRate: Int(rate), channels: 1)
    }
}
