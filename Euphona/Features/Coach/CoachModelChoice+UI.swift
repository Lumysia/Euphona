import EuphonaKit
import SwiftUI

extension CoachModelChoice {
    /// The choices this device can use: Private Cloud Compute only where the system has it.
    static var offered: [CoachModelChoice] {
        allCases.filter { $0 != .privateCloud || LanguageCoach.isAvailable(.privateCloud) }
    }

    /// On the device when Apple Intelligence is ready there, otherwise the built-in coach.
    static var recommended: CoachModelChoice { LanguageCoach.isAvailable(.onDevice) ? .onDevice : .off }

    var title: LocalizedStringResource {
        switch self {
        case .onDevice: .coachModelOnDevice
        case .privateCloud: .coachModelCloud
        case .off: .coachModelOff
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .onDevice: .coachModelOnDeviceDetail
        case .privateCloud: .coachModelCloudDetail
        case .off: .coachModelOffDetail
        }
    }
}

/// The coach's model in Settings, with a note when the chosen one cannot run here.
struct CoachModelSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker(selection: $settings.coachModel) {
                ForEach(CoachModelChoice.offered, id: \.self) { Text($0.title).tag($0) }
            } label: { Text(.settingsCoachModel) }
        } footer: {
            if settings.coachModel != .off, !LanguageCoach.isAvailable(settings.coachModel) {
                Text(.settingsCoachModelUnavailable)
            } else {
                Text(settings.coachModel.subtitle)
            }
        }
    }
}
