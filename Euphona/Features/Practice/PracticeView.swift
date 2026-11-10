import SwiftUI

/// Practice tools: live pitch, timbre and resonance, spectrum, piano and Voice Quality.
struct PracticeView: View {
    @Environment(\.theme) private var theme
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ToolCard(title: .pitchTitle, subtitle: .pitchReferenceSubtitle, symbol: "waveform.path",
                             accent: theme.deepPink, tool: .pitch)
                    ToolCard(title: .timbreTitle, subtitle: .timbreSubtitle, symbol: "person.wave.2",
                             accent: theme.purple, tool: .timbre)
                    ToolCard(title: .resonanceTitle, subtitle: .resonanceSubtitle, symbol: "circle.hexagongrid",
                             accent: theme.teal, tool: .resonance)
                    ToolCard(title: .spectrumTitle, subtitle: .moreSpectrumDescription, symbol: "chart.bar.xaxis",
                             accent: theme.deepBlue, tool: .spectrum)
                    ToolCard(title: .pianoTitle, subtitle: .morePianoDescription, symbol: "pianokeys",
                             accent: theme.pink, tool: .piano)
                    ToolCard(title: .voiceQualityTitle, subtitle: .voiceQualityCardSubtitle, symbol: "waveform.and.person.filled",
                             accent: theme.ease, tool: .voiceQuality)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(Text(.tabPractice))
            .appRoutes()
            .toolbar { RootToolbar() }
        }
    }
}

private struct ToolCard: View {
    var title: LocalizedStringResource
    var subtitle: LocalizedStringResource
    var symbol: String
    var accent: Color
    var tool: PracticeTool

    var body: some View {
        NavigationLink(value: Route.practice(tool)) {
            HStack(spacing: 16) {
                IconTile(symbol: symbol, accent: accent, side: 72, breathes: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.bold())
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 28))
            .foregroundStyle(.primary)
            .contentShape(.rect)
            .hoverCard(cornerRadius: 28)
        }
        .buttonStyle(.card)
    }
}
