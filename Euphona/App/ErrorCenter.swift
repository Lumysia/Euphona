import Observation
import SwiftUI

/// Failures the user should know about, shown as one system alert at the root of each window.
@MainActor @Observable
final class ErrorCenter {
    struct Failure: Identifiable {
        let id = UUID()
        var title: LocalizedStringResource
        var message: LocalizedStringResource = .errorTryAgain
    }

    var current: Failure?

    /// Runs `work` and reports `title` if it throws.
    func attempt(_ title: LocalizedStringResource, _ work: () throws -> Void) {
        do { try work() } catch { report(title) }
    }

    func report(_ title: LocalizedStringResource, message: LocalizedStringResource = .errorTryAgain) {
        current = Failure(title: title, message: message)
    }
}

/// Presents the error center's failures in the view the user is looking at: `isActive` is false
/// while this view has a sheet or cover over it, and on Mac only the key window shows the alert.
private struct ErrorAlerts: ViewModifier {
    var errors: ErrorCenter
    var isActive: Bool
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    private var isFrontmost: Bool { activeState == .key }
    #else
    private var isFrontmost: Bool { true }
    #endif

    func body(content: Content) -> some View {
        content.alert(item: Binding(get: { isActive && isFrontmost ? errors.current : nil }, set: { errors.current = $0 })) { failure in
            Alert(title: Text(failure.title), message: Text(failure.message), dismissButton: .default(Text(.actionOk)))
        }
    }
}

extension View {
    func errorAlerts(_ errors: ErrorCenter, isActive: Bool = true) -> some View {
        modifier(ErrorAlerts(errors: errors, isActive: isActive))
    }
}
