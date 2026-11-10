@preconcurrency import AVFAudio
import Foundation

/// A polyphonic sine synth with a piano-like envelope: 6 ms linear attack,
/// sustain decaying as 0.65 + 0.35·e^(−0.9 t), 8 ms release, and tanh soft clipping.
///
/// It lives in EuphonaKit, which has no default actor isolation: the render block runs on the realtime
/// audio thread. All state is guarded by `lock`.
public final class PianoSynth: @unchecked Sendable {
    public static let sampleRate = 48_000.0
    static let attack = 0.006
    static let release = 0.008
    static let drive = 1.8

    private struct Voice {
        var frequency: Double
        var phase = 0.0
        var age = 0.0
        var releasedAt: Double?
    }

    let engine = AVAudioEngine()
    private let lock = NSLock()
    private var voices: [Int: Voice] = [:]
    private var started = false

    public static func frequency(midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    public init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        let source = AVAudioSourceNode(format: format) { @Sendable [unowned self] _, _, frameCount, buffers in
            let output = UnsafeMutableAudioBufferListPointer(buffers)[0]
            let samples = output.mData!.assumingMemoryBound(to: Float.self)
            render(into: samples, count: Int(frameCount))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    public func noteOn(_ midi: Int) {
        if !started, !engine.isInManualRenderingMode {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            try? engine.start()
            started = true
        }
        lock.withLock {
            // Pressing a ringing key restarts its envelope without a click.
            var voice = voices[midi] ?? Voice(frequency: Self.frequency(midi: midi))
            voice.age = 0
            voice.releasedAt = nil
            voices[midi] = voice
        }
    }

    public func noteOff(_ midi: Int) {
        lock.withLock {
            guard var voice = voices[midi] else { return }
            voice.releasedAt = voice.age
            voices[midi] = voice
        }
    }

    public func stop() {
        lock.withLock { voices.removeAll() }
        engine.stop()
        started = false
    }

    private func render(into samples: UnsafeMutablePointer<Float>, count: Int) {
        lock.lock()
        defer { lock.unlock() }
        let step = 1 / Self.sampleRate
        let normalizer = tanh(Self.drive)
        for frame in 0..<count {
            var mix = 0.0
            for key in voices.keys {
                guard var voice = voices[key] else { continue }
                var gain = voice.age < Self.attack ? voice.age / Self.attack : 0.65 + 0.35 * exp(-0.9 * voice.age)
                if let released = voice.releasedAt {
                    let fade = 1 - (voice.age - released) / Self.release
                    if fade <= 0 { voices[key] = nil; continue }
                    gain *= fade
                }
                mix += tanh(sin(voice.phase) * gain * Self.drive) / normalizer * 0.5
                voice.phase += 2 * .pi * voice.frequency * step
                if voice.phase > 2 * .pi { voice.phase -= 2 * .pi }
                voice.age += step
                voices[key] = voice
            }
            samples[frame] = Float(tanh(mix))
        }
    }
}
