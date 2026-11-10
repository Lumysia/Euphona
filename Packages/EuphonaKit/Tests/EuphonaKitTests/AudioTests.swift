import Foundation
import Testing
@testable import EuphonaKit

struct AudioTests {
    @Test func aacRoundTripKeepsTheDuration() async throws {
        let speech = try await TestAudio.load("feminine")
        let data = try AudioEncoder.aac(speech)
        #expect(data.count < speech.samples.count * 2 / 3)
        let url = FileManager.default.temporaryDirectory.appending(path: "roundtrip.\(AudioEncoder.fileExtension)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try await AudioFileReader.read(url)
        #expect(abs(decoded.duration - speech.duration) < 0.1)
    }

    @Test func aLongFileIsReadFromItsStart() async throws {
        let start = try await AudioFileReader.read(TestAudio.directory.appending(path: "feminine.wav"), maximumSeconds: 2)
        #expect(abs(start.duration - 2) < 0.05 && start.channels == 1)
    }
}
