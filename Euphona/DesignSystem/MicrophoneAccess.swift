import SwiftUI

/// Why a recording could not start or finish, shared by every screen that records.
enum CaptureFailure: Equatable {
    case microphoneDenied, couldNotStart, tooLittleSpeech, analysisFailed, unreadableFile

    var message: LocalizedStringResource {
        switch self {
        case .microphoneDenied: .recordPermissionDenied
        case .couldNotStart: .errorRecordingStart
        case .tooLittleSpeech: .errorSpeechDurationShort
        case .analysisFailed: .errorAnalysisFailed
        case .unreadableFile: .errorUnreadableFile
        }
    }
}

/// Opens the place where the user can allow microphone access again: this app's page in Settings
/// on iPhone and iPad, Privacy & Security ▸ Microphone on Mac.
struct OpenMicrophoneSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(Self.url) } label: { Text(.actionOpenSettings) }
    }

    static var url: URL {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)!
        #else
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        #endif
    }
}

/// A failed recording or tool start: what went wrong, and the one action that can fix it.
struct CaptureFailureView: View {
    var failure: CaptureFailure
    var title: LocalizedStringResource = .analysisFailed
    var retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { Image(systemName: failure == .microphoneDenied ? "mic.slash" : "waveform.slash") }
        } description: {
            Text(failure.message)
        } actions: {
            if failure == .microphoneDenied {
                OpenMicrophoneSettingsButton().buttonStyle(.glassProminent)
            } else {
                Button(action: retry) { Text(.recordingAgain) }.buttonStyle(.glassProminent)
            }
        }
    }
}
