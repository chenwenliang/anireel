import SwiftUI

/// 示例: the same sample works as the empty feed, with what each style is good for.
struct SamplesView: View {
    let samples: [SampleWork]
    let onShoot: (StyleID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Samples illustrate each style. Your clip looks like the live preview.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                    ForEach(samples) { sample in
                        SampleCard(sample: sample) { onShoot(sample.style) }
                    }
                }
                .padding(Theme.Spacing.gutter)
            }
            .background(Theme.Palette.groupedBackground)
            .navigationTitle("Samples")
        }
    }
}

private struct SampleCard: View {
    let sample: SampleWork
    let onShoot: () -> Void

    private var descriptor: StyleDescriptor? { StyleRegistry.shipping.pack(for: sample.style)?.descriptor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StyleCover(style: sample.style, cornerRadius: Theme.Radius.large)
                .aspectRatio(4 / 5, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Pill(text: Text("Sample work"), systemImage: "sparkles", tone: .accent).padding(12)
                }
            Text(descriptor?.title ?? sample.style.rawValue)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.ink)
            Text(sample.explanation)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onShoot) {
                Label("Shoot one in this style", systemImage: "camera.fill")
            }
            .buttonStyle(.gradient)
        }
        .padding(14)
        .cardSurface()
    }
}

extension SampleWork {
    /// What the style does and what it suits; shown in 示例.
    var explanation: LocalizedStringKey {
        switch style {
        case GhibliStylePack.id: "Turns everyday scenes into soft, hand-painted frames. Best for landscapes, streets, pets and golden-hour light."
        case ChibiStylePack.id: "Bold outlines and candy colors make faces and small things pop. Best for selfies, friends and snacks."
        case NPRStylePack.id: "Bright skies and clear light, like a still from an animated film. Best for skies, streets and wide views."
        default: "A live animation style."
        }
    }
}
