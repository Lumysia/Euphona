import SwiftUI

/// The iOS zoom transition, used only for the full-screen analysis growing out of Analyze Voice.
/// Pushes inside a tab keep the standard slide: the zoom's settling spring blocks taps for a while after
/// going back, which made card-to-card browsing feel stuck. Mac keeps the standard presentation.
extension View {
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        matchedTransitionSource(id: id, in: namespace)
        #else
        self
        #endif
    }

    func zoomDestination(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        navigationTransition(.zoom(sourceID: id, in: namespace))
        #else
        self
        #endif
    }
}
