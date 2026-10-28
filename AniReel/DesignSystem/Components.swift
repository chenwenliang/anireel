import SwiftUI

/// The A-with-play mark. `gradient` fills it with the mark gradient (on light surfaces);
/// otherwise it is plain white (on gradients and video).
struct BrandMark: View {
    var size: CGFloat = 32
    var gradient = false

    var body: some View {
        Group {
            if gradient {
                Theme.Gradients.mark.mask { Image("BrandMark").resizable().scaledToFit() }
            } else {
                Image("BrandMark").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The "AniReel" wordmark with the mark in front.
struct Wordmark: View {
    var onDark = false

    var body: some View {
        HStack(spacing: 6) {
            BrandMark(size: 26, gradient: !onDark)
            Text(verbatim: "AniReel")
                .font(Theme.Typography.wordmark)
                .foregroundStyle(onDark ? Color.white : Theme.Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "AniReel"))
    }
}

/// Primary call to action: full-width gradient capsule.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Gradients.mark, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary action: hairline capsule on light surfaces, frosted capsule on dark ones.
struct SecondaryButtonStyle: ButtonStyle {
    var onDark = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(onDark ? Color.white : Theme.Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if onDark {
                    Capsule().fill(.ultraThinMaterial)
                } else {
                    Capsule().fill(Theme.Palette.surface)
                    Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var gradient: GradientButtonStyle { GradientButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var secondaryOnDark: SecondaryButtonStyle { SecondaryButtonStyle(onDark: true) }
}

/// Small capsule label: style badges, 「示例作品」, quota status.
struct Pill: View {
    enum Tone { case accent, glass, light }

    let text: Text
    var systemImage: String?
    var tone: Tone = .glass

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            text
        }
        .font(Theme.Typography.badge)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tone == .light ? Theme.Palette.ink : .white)
        .background {
            switch tone {
            case .accent: Capsule().fill(Theme.accent)
            case .glass: Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            case .light: Capsule().fill(Theme.Palette.groupedBackground)
            }
        }
    }
}

/// Shared empty / error / unsupported state: gradient mark tile, title, message, optional action.
struct StateMessageView<Actions: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var onDark = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Theme.Gradients.aurora, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.title)
                .multilineTextAlignment(.center)
                .foregroundStyle(onDark ? Color.white : Theme.Palette.ink)
            Text(message)
                .font(Theme.Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(onDark ? Color.white.opacity(0.7) : Theme.Palette.secondaryInk)
            actions()
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 420)
    }
}

extension StateMessageView where Actions == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey, onDark: Bool = false) {
        self.init(systemImage: systemImage, title: title, message: message, onDark: onDark) { EmptyView() }
    }
}

/// A style's procedural sample cover (docs/PHASE7_BRIEF.md), aspect-filled and clipped.
struct StyleCover: View {
    let style: StyleID
    var cornerRadius: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.Palette.groupedBackground)
            .overlay {
                if let name = SampleWork.coverAssetName(for: style) {
                    Image(name).resizable().scaledToFill()
                } else {
                    Theme.Gradients.aurora
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
