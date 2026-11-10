import EuphonaKit
import SwiftUI

struct AboutView: View {
    private struct Credit: Identifiable {
        var name: String
        var detail: String
        var url: String
        var id: String { name }
    }

    /// What the analysis engine is built from and trained on.
    private static let modelsAndData = [
        Credit(name: "SpeechBrain ECAPA-TDNN", detail: "Apache-2.0", url: "https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb"),
        Credit(name: "Silero VAD", detail: "MIT", url: "https://github.com/snakers4/silero-vad"),
        Credit(name: "SwiftF0", detail: "MIT", url: "https://github.com/lars76/swift-f0"),
        Credit(name: "Mozilla Common Voice", detail: "CC0-1.0", url: "https://commonvoice.mozilla.org"),
        Credit(name: "Google FLEURS", detail: "CC BY 4.0", url: "https://huggingface.co/datasets/google/fleurs"),
        Credit(name: "Perceptual Voice Qualities Database", detail: "CC BY 4.0", url: "https://data.mendeley.com/datasets/9dz247gnyb/1"),
    ]

    private static let openSource = [
        Credit(name: "Euphona", detail: "GPL-3.0-only", url: "https://github.com/Lumysia/Euphona"),
        Credit(name: "ONNX Runtime", detail: "MIT", url: "https://github.com/microsoft/onnxruntime"),
    ]

    private static let inspiredBy = [
        Credit(name: "Project Pitchee", detail: "", url: "https://github.com/Project-Pitchee"),
        Credit(name: "Pitchee for Android", detail: "GPL-3.0-only", url: "https://github.com/Project-Pitchee/Pitchee-Android"),
    ]

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(.aboutIcon)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .accessibilityHidden(true)
                    Text(.appName).font(.title.bold())
                    Text(.aboutTagline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text(.settingsVersionFormat(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: EuphonaAnalyzer.modelVersion).font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                Text(.aboutPrivacy).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            Section {
                Text(verbatim: "Livia Zhang")
            } header: { Text(.settingsAuthors) }
            Section {
                rows(Self.modelsAndData)
            } header: { Text(.aboutModelsData) } footer: { Text(.aboutModelsFooter) }
            Section {
                rows(Self.openSource)
            } header: { Text(.settingsOpenSource) }
            Section {
                rows(Self.inspiredBy)
            } header: {
                Text(.aboutBasedOn)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(.settingsAbout))
    }

    private func rows(_ credits: [Credit]) -> some View {
        ForEach(credits) { credit in
            Link(destination: URL(string: credit.url)!) {
                LabeledContent {
                    Text(verbatim: credit.detail)
                } label: {
                    Text(verbatim: credit.name).foregroundStyle(.tint)
                }
            }
        }
    }
}
