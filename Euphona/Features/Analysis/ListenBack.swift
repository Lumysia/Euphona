import EuphonaKit
import SwiftUI

/// This recording and the one it is compared with, one tap each, so the ear can judge the change
/// the scores describe. Starting one stops the other.
struct ListenBack: View {
    /// The result screen's own player, shared with its timeline.
    var current: RecordingPlayback
    @State private var previous: RecordingPlayback
    private let previousDate: Date

    init(current: RecordingPlayback, previous recording: PreviousRecording) {
        self.current = current
        _previous = State(initialValue: RecordingPlayback(data: recording.audio, duration: recording.duration))
        previousDate = recording.date
    }

    var body: some View {
        row(current, title: Text(.listenBackThisTime), other: previous)
        row(previous, title: Text(previousDate, format: .relative(presentation: .named)), other: current)
            .onDisappear { previous.stop() }
    }

    private func row(_ playback: RecordingPlayback, title: Text, other: RecordingPlayback) -> some View {
        Button {
            if other.isPlaying { other.toggle() }
            if !playback.isPlaying { playback.seek(to: 0) }
            playback.toggle()
        } label: {
            HStack {
                Label { title } icon: {
                    Image(systemName: playback.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text(verbatim: playback.duration.clock).foregroundStyle(.secondary).monospacedDigit()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!playback.isAvailable)
    }
}
