#if DEBUG
import SwiftUI

#if os(iOS)
/// What the person holding the device sees before and after a take: they start it themselves, and nothing
/// outside the app explains it. Debug only, so not localized.
struct DemoTourCard: View {
    private let tour = DemoTour.shared

    var body: some View {
        switch tour.phase {
        case .ready:
            Button(action: tour.begin) {
                card(symbol: "record.circle", tint: .red, lines: [
                    "Tap to start the review recording.",
                    "Then put the device down for about 3 minutes.",
                ], note: note)
            }
            .buttonStyle(.plain)
        case .finished:
            card(symbol: "checkmark.circle.fill", tint: .green, lines: [
                "Done, you can take the device back.",
            ], note: nil)
        case .off, .starting, .recording, .closing:
            EmptyView()
        }
    }

    private var note: String {
        switch tour.setback {
        case .leftApp: "The last take stopped when the app was left. Stay in Euphona until it says Done."
        case .notStarted: "Recording didn't start. When iOS asks, choose Record Screen."
        case nil: "When iOS asks, choose Record Screen."
        }
    }

    private func card(symbol: String, tint: Color, lines: [String], note: String?) -> some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 72))
                .foregroundStyle(tint)
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line).font(.title2.weight(.semibold))
            }
            if let note {
                Text(verbatim: note).font(.body).foregroundStyle(.secondary).padding(.top, 12)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contentShape(Rectangle())
    }
}
#endif
#endif
