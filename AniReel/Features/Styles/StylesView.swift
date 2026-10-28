import SwiftUI

/// 风格: one large card per style pack, plus the coming-soon cell. Replaces the Phase 1 picker.
struct StylesView: View {
    let packs: [any StylePack]
    let lastUsed: StyleID?
    let onShoot: (StyleID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Every style runs live in the camera. What you see is what gets saved.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                    ForEach(packs, id: \.descriptor.id) { pack in
                        StylePackCard(descriptor: pack.descriptor, isLastUsed: pack.descriptor.id == lastUsed) {
                            onShoot(pack.descriptor.id)
                        }
                    }
                    ComingSoonCard()
                }
                .padding(Theme.Spacing.gutter)
            }
            .background(Theme.Palette.groupedBackground)
            .navigationTitle("Styles")
        }
    }
}

private struct StylePackCard: View {
    let descriptor: StyleDescriptor
    let isLastUsed: Bool
    let onShoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StyleCover(style: descriptor.id)
                .frame(height: 220)
                .overlay(alignment: .topLeading) {
                    if isLastUsed {
                        Pill(text: Text("Last used"), systemImage: "clock.arrow.circlepath").padding(12)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(descriptor.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.ink)
                Text(descriptor.subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                Button(action: onShoot) {
                    Label("Shoot", systemImage: "camera.fill")
                }
                .buttonStyle(.gradient)
                .padding(.top, 8)
                .accessibilityLabel(Text("Shoot in \(descriptor.title)"))
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .cardSurface()
    }
}

/// Shows that styles are add-ons: new StylePacks appear here and in the camera.
struct ComingSoonCard: View {
    var compact = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                .background(Theme.Gradients.aurora, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("More styles coming soon").font(Theme.Typography.headline)
                if !compact {
                    Text("New looks will appear here as they're added.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
