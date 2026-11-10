@preconcurrency import AVFAudio
import Testing
@testable import EuphonaKit

struct PianoSynthTests {
    /// Renders offline off the main actor, the way the realtime audio thread calls the render block.
    @Test func rendersANoteAndReleasesIt() throws {
        let synth = PianoSynth()
        let format = AVAudioFormat(standardFormatWithSampleRate: PianoSynth.sampleRate, channels: 1)!
        try synth.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4800)
        try synth.engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: synth.engine.manualRenderingFormat, frameCapacity: 4800)!

        func peak() throws -> Float {
            _ = try synth.engine.renderOffline(4800, to: buffer)
            return UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)).map(abs).max() ?? 0
        }

        #expect(try peak() == 0)
        synth.noteOn(57)
        #expect(try peak() > 0.1)
        synth.noteOff(57)
        _ = try peak()
        #expect(try peak() < 0.001)
        #expect(abs(PianoSynth.frequency(midi: 69) - 440) < 1e-9)
    }
}
