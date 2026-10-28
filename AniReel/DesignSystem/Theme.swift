import SwiftUI

/// Design tokens shared by every screen (docs/PHASE7_BRIEF.md, D9): aurora gradient, duotone mark
/// gradient, coral as the single warm accent, light surfaces, hairlines and soft shadows.
/// scripts/make_placeholder_art.py mirrors the brand colours for the icon and covers.
enum Theme {
    enum Palette {
        static let cyan = Color(hex: 0x22C1EE)
        static let blue = Color(hex: 0x2F6BFF)
        static let violet = Color(hex: 0x8B5CF6)
        static let coral = Color(hex: 0xFF6B4A)
        static let ink = Color(hex: 0x15131F)
        static let secondaryInk = Color(hex: 0x6B6878)
        static let surface = Color.white
        static let groupedBackground = Color(hex: 0xF4F4F8)
        static let hairline = Color.black.opacity(0.08)
        /// Background of immersive screens (feed, camera, result).
        static let stage = Color.black
    }

    /// The single warm accent: record button, selected states, badges.
    static let accent = Palette.coral

    enum Gradients {
        static let aurora = LinearGradient(
            colors: [Palette.cyan, Palette.blue, Palette.violet],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let mark = LinearGradient(
            stops: [
                .init(color: Palette.coral, location: 0),
                .init(color: Palette.coral, location: 0.2),
                .init(color: Palette.blue, location: 0.6),
                .init(color: Palette.violet, location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        /// Keeps white text legible over video and covers.
        static let scrimBottom = LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        static let scrimTop = LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
    }

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum Spacing {
        static let gutter: CGFloat = 20
        static let stack: CGFloat = 12
    }

    enum Typography {
        static let display = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        static let headline = Font.system(.headline, design: .rounded)
        static let body = Font.body
        static let caption = Font.footnote
        static let badge = Font.caption.weight(.semibold)
        static let wordmark = Font.system(size: 22, weight: .heavy, design: .rounded)
    }

    enum Shadow {
        static let soft = Color.black.opacity(0.08)
        static let softRadius: CGFloat = 16
        static let softY: CGFloat = 6
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// The standard white card: medium radius, hairline, soft shadow.
    func cardSurface() -> some View {
        background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.Palette.hairline))
            .shadow(color: Theme.Shadow.soft, radius: Theme.Shadow.softRadius, y: Theme.Shadow.softY)
    }
}
