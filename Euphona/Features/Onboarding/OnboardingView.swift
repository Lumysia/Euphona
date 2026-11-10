import EuphonaKit
import SwiftUI

/// First launch, as a welcome sheet over the app: the voice direction, then iCloud sync.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var goal: VoiceGoal?
    @State private var coach = CoachModelChoice.recommended
    @State private var showsCoach = false
    @State private var showsSync = false

    var body: some View {
        NavigationStack {
            WelcomePage(symbol: nil, title: .onboardingPreferencesTitle, subtitle: .onboardingPreferencesSubtitle) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(.onboardingPreferencesPrompt).font(.headline)
                    ForEach(VoiceGoal.allCases, id: \.self) { option in
                        VoiceGoalCard(goal: option, isSelected: goal == option) { goal = option }
                    }
                }
            } actions: {
                Button { showsCoach = true } label: { WelcomeButtonLabel(text: .onboardingContinue) }
                    .buttonStyle(.glassProminent)
                    .disabled(goal == nil)
            }
            .navigationDestination(isPresented: $showsCoach) {
                WelcomePage(symbol: "graduationcap", title: .onboardingCoachTitle, subtitle: .onboardingCoachBody) {
                    VStack(spacing: 12) {
                        ForEach(CoachModelChoice.offered, id: \.self) { option in
                            ChoiceCard(title: option.title, subtitle: option.subtitle, isSelected: coach == option) { coach = option }
                        }
                    }
                } actions: {
                    Button { showsSync = true } label: { WelcomeButtonLabel(text: .onboardingContinue) }
                        .buttonStyle(.glassProminent)
                }
                .navigationDestination(isPresented: $showsSync) { syncPage }
            }
        }
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
    }

    private var syncPage: some View {
        Group {
                WelcomePage(symbol: "icloud", title: .onboardingIcloudTitle, subtitle: .onboardingIcloudBody) {
                    EmptyView()
                } actions: {
                    Button { finish(syncs: true) } label: { WelcomeButtonLabel(text: .onboardingIcloudUse) }
                        .buttonStyle(.glassProminent)
                    Button { finish(syncs: false) } label: { Text(.onboardingIcloudNotNow).padding(.vertical, 4) }
                        .buttonStyle(.borderless)
                }
        }
    }

    private func finish(syncs: Bool) {
        guard let goal else { return }
        settings.completeOnboarding(goal: goal, syncsWithICloud: syncs, coachModel: coach)
    }
}

/// One page of the welcome sheet: a symbol or the orb, a centred title and text, content, and the
/// buttons pinned to the bottom, as in Apple's own welcome screens.
private struct WelcomePage<Content: View, Actions: View>: View {
    var symbol: String?
    var title: LocalizedStringResource
    var subtitle: LocalizedStringResource
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    if let symbol {
                        Image(systemName: symbol)
                            .scaledFont(size: 64)
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                            .frame(height: 88)
                    } else {
                        VoiceOrb(balance: 0.6, halo: false).frame(width: 88, height: 88)
                    }
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 8) { actions }
                .controlSize(.large)
                .frame(maxWidth: 460)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
        }
        .toolbarTitleDisplayMode(.inline)
    }
}

private struct WelcomeButtonLabel: View {
    var text: LocalizedStringResource

    var body: some View {
        Text(text).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
    }
}

/// One selectable voice direction.
struct VoiceGoalCard: View {
    let goal: VoiceGoal
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        ChoiceCard(title: goal.title, subtitle: goal.subtitle, isSelected: isSelected, select: select)
    }
}

/// One option of a welcome-sheet choice: a radio mark, a title and a line of explanation.
struct ChoiceCard: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .contentShape(.rect)
            .background(.background.secondary, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
            }
        }
        .buttonStyle(.card)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension VoiceGoal {
    var title: LocalizedStringResource {
        switch self {
        case .feminine: .voiceProfileFeminineTitle
        case .masculine: .voiceProfileMasculineTitle
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .feminine: .voiceProfileFeminineDescription
        case .masculine: .voiceProfileMasculineDescription
        }
    }
}
