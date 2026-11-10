@preconcurrency import AVFAudio

/// The result's sound: clear, piano-like notes (a struck tone with slightly stretched partials that fade
/// at their own rates, in a small room) climbing a pentatonic scale from low to high. A score maps to a
/// note on the scale, so the phrase stops where the result lands: higher results end higher.
@MainActor
final class ResultChime {
    /// C major pentatonic from C4 over three octaves, ending on C7.
    static let scale: [Int] = (0..<3).flatMap { octave in [0, 2, 4, 7, 9].map { 60 + 12 * octave + $0 } } + [96]
    private static let voices = 10
    private static let sampleRate = 44_100.0
    private static let noteSeconds = 1.6

    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var notes: [Int: AVAudioPCMBuffer] = [:]
    // Stereo: the reverb unit takes no mono input.
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    private var reconfigured: NSObjectProtocol?

    /// Builds and starts the graph after the audio session is set, so a session change can't
    /// reconfigure it under the players; a disconnected player raises when played.
    private func running() -> AVAudioEngine? {
        if let engine, engine.isRunning { return engine }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        let engine = AVAudioEngine()
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 18
        // The players meet in a mixer (one input bus each) before the reverb, whose single input
        // would keep only the last connection.
        let voices = AVAudioMixerNode()
        engine.attach(reverb)
        engine.attach(voices)
        engine.connect(voices, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        players = (0..<Self.voices).map { bus in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: voices, fromBus: 0, toBus: bus, format: format)
            return player
        }
        guard (try? engine.start()) != nil else { return nil }
        // A route or configuration change stops the engine; the next note builds a fresh one.
        if let reconfigured { NotificationCenter.default.removeObserver(reconfigured) }
        reconfigured = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine = nil }
        }
        self.engine = engine
        return engine
    }

    /// The scale step for a 0–100 value.
    static func step(_ value: Double) -> Int {
        Int((min(max(value, 0), 100) / 100 * Double(scale.count - 1)).rounded())
    }

    /// Plays one step of the scale; `loudness` 0–1.
    func play(step: Int, loudness: Double = 0.8) {
        play(midi: Self.scale[min(max(step, 0), Self.scale.count - 1)], loudness: loudness)
    }

    /// The landing: the final note with its fifth and octave, softly, as a bell-like close.
    func land(step: Int) {
        let midi = Self.scale[min(max(step, 0), Self.scale.count - 1)]
        play(midi: midi, loudness: 0.75)
        play(midi: midi + 7, loudness: 0.3)
        play(midi: midi + 12, loudness: 0.25)
    }

    func stop() {
        players.forEach { $0.stop() }
        engine?.stop()
        engine = nil
        if let reconfigured { NotificationCenter.default.removeObserver(reconfigured) }
        reconfigured = nil
    }

    private func play(midi: Int, loudness: Double) {
        guard running() != nil, !players.isEmpty else { return }
        let buffer = notes[midi] ?? Self.render(midi: midi, format: format)
        notes[midi] = buffer
        let player = players[next]
        next = (next + 1) % players.count
        player.stop()
        player.volume = Float(min(max(loudness, 0), 1))
        player.scheduleBuffer(buffer)
        player.play()
    }

    /// A struck tone: six partials, slightly stretched like a piano string, higher ones fading faster,
    /// with a 3 ms attack so it starts crisp without a click.
    private static func render(midi: Int, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(noteSeconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0], right = buffer.floatChannelData![1]
        let f0 = 440 * pow(2, Double(midi - 69) / 12)
        let amplitudes = [1.0, 0.42, 0.24, 0.12, 0.07, 0.04]
        let stretch = 0.0004
        // Higher notes ring shorter, as on a piano.
        let ring = 1.1 * pow(2, -Double(midi - 60) / 36)
        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            for (index, amplitude) in amplitudes.enumerated() {
                let k = Double(index + 1)
                let frequency = k * f0 * (1 + stretch * k * k).squareRoot()
                guard frequency < sampleRate / 2 else { break }
                sample += amplitude * exp(-t / (ring / (1 + 0.7 * (k - 1)))) * sin(2 * .pi * frequency * t)
            }
            let attack = min(t / 0.003, 1)
            let tail = min((noteSeconds - t) / 0.05, 1)
            let value = Float(0.32 * sample * attack * tail)
            left[frame] = value
            right[frame] = value
        }
        return buffer
    }
}
