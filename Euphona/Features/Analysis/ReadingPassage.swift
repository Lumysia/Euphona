import EuphonaKit
import SwiftUI

/// The six official reading passages, or the person's own text.
struct ReadingPassage {
    static let officialCount = 6

    var title: String
    var text: String

    static func official(_ index: Int) -> ReadingPassage {
        let number = min(max(index, 0), officialCount - 1) + 1
        return ReadingPassage(
            title: localized(key: "reading_passage_titles_\(number)"),
            text: localized(key: "reading_passage_texts_\(number)")
        )
    }

    @MainActor static func active(_ settings: AppSettings) -> ReadingPassage {
        let custom = settings.customPassage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.passageSource == .custom, !custom.isEmpty else { return official(settings.officialPassageIndex) }
        return ReadingPassage(title: String(localized: .passageCustomTitle), text: custom)
    }
}

/// The passage to read aloud, scrollable, filling the space between the stage and the record button.
/// Its title is a menu for switching passages; switching is off while recording.
struct ReadingPassageView: View {
    var canSwitch: Bool
    @Environment(AppSettings.self) private var settings
    @State private var editsCustom = false

    var body: some View {
        let passage = ReadingPassage.active(settings)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PassageMenu(title: passage.title, editsCustom: $editsCustom)
                    .disabled(!canSwitch)
                Text(verbatim: passage.text)
                    .font(.title3)
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .accessibilityIdentifier("analysis.passage")
        .scrollBounceBehavior(.basedOnSize)
        .id(passage.text)
        .transition(.blurReplace)
        .animation(.smooth, value: passage.text)
        .sheet(isPresented: $editsCustom) { CustomPassageEditor() }
    }
}

private struct PassageMenu: View {
    var title: String
    @Binding var editsCustom: Bool
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Menu {
            Picker(selection: Binding<Int?>(
                get: { settings.passageSource == .official ? settings.officialPassageIndex : nil },
                set: { if let index = $0 { settings.passageSource = .official; settings.officialPassageIndex = index } }
            )) {
                ForEach(0..<ReadingPassage.officialCount, id: \.self) { index in
                    Text(verbatim: ReadingPassage.official(index).title).tag(Optional(index))
                }
            } label: { Text(.passageSourceOfficial) }
            .pickerStyle(.inline)
            Section {
                Button { editsCustom = true } label: {
                    Label { Text(.passageSourceCustom) } icon: { Image(systemName: "square.and.pencil") }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: title)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .sensoryFeedback(.selection, trigger: settings.officialPassageIndex)
        .accessibilityLabel(Text(.settingsPassages))
        .accessibilityValue(Text(verbatim: title))
    }
}

/// Edits the person's own passage in a card styled like the passage it becomes; Done switches to it.
private struct CustomPassageEditor: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // The card fills the sheet and the placeholder is an overlay, so typing never resizes it.
                TextEditor(text: $text)
                    .font(.title3)
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(.passageEditorPlaceholder)
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(14)
                    .frame(maxHeight: .infinity)
                    .background(.background.secondary, in: .rect(cornerRadius: 26))

                Label { Text(.passageEditorTip) } icon: { Image(systemName: "lightbulb.max").foregroundStyle(.yellow) }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .navigationTitle(Text(.passageCustomTitle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        settings.customPassage = trimmed
                        settings.passageSource = .custom
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
        .presentationDetents([.large])
        .onAppear {
            text = settings.customPassage
            focused = true
        }
    }
}

/// Looks up a catalog string by a key built at runtime. Interpolating inside `LocalizationValue`
/// would turn the variable part into a format argument.
func localized(key: String) -> String {
    String(localized: String.LocalizationValue(key))
}
