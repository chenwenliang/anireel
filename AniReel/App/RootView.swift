import SwiftUI

struct RootView: View {
    let registry: StyleRegistry
    /// `nil` means the device is below the A13 floor (docs/DECISIONS.md D1).
    let deviceTier: DeviceTier?
    @State private var account = AccountStore.live()
    @State private var preferences = PreferencesStore()
    @State private var library = ClipLibrary()

    var body: some View {
        if deviceTier == nil {
            UnsupportedDeviceView()
        } else {
            AppShell(registry: registry)
                .fullScreenCover(isPresented: Binding(
                    get: { !preferences.preferences.hasCompletedOnboarding },
                    set: { if !$0 { preferences.preferences.hasCompletedOnboarding = true } }
                )) {
                    OnboardingView {
                        preferences.preferences.hasCompletedOnboarding = true
                    }
                }
                .environment(account)
                .environment(preferences)
                .environment(library)
                .task { await account.restoreSession() }
        }
    }
}

/// The one navigation model (D9): 作品 | 风格 | centre camera button | 示例 | 我的,
/// with the camera presented full screen over whichever tab is open.
private struct AppShell: View {
    let registry: StyleRegistry
    @State private var shell = ShellState()
    @Environment(AccountStore.self) private var account
    @Environment(PreferencesStore.self) private var preferences
    @Environment(ClipLibrary.self) private var library

    private var styles: [StyleID] { registry.packs.map(\.descriptor.id) }
    private var samples: [SampleWork] { SampleWork.catalog(for: styles) }

    var body: some View {
        tabContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ShellTabBar(selected: shell.tab, onSelect: { shell.select($0) }, onCamera: { openCamera(nil) })
            }
            .fullScreenCover(item: $shell.camera) { route in
                CameraScreen(
                    packs: registry.packs,
                    style: route.style,
                    account: account,
                    library: library,
                    defaults: preferences.preferences.capture,
                    onClose: { shell.closeCamera() },
                    onFinish: { shell.finishCapture() },
                    onOpenMyClips: { shell.openMyClips() }
                )
            }
    }

    @ViewBuilder private var tabContent: some View {
        switch shell.tab {
        case .works:
            HomeFeedView(
                samples: samples,
                onShoot: { openCamera($0) },
                onOpenMyClips: { shell.openMyClips() },
                onOpenProfile: { shell.select(.me) }
            )
        case .styles:
            StylesView(packs: registry.packs, lastUsed: preferences.preferences.lastStyle) { openCamera($0) }
        case .samples:
            SamplesView(samples: samples) { openCamera($0) }
        case .me:
            ProfileView(path: $shell.profilePath, onShoot: { openCamera(nil) })
        }
    }

    private func openCamera(_ style: StyleID?) {
        shell.openCamera(style: style, lastUsed: preferences.preferences.lastStyle, available: styles)
    }
}

/// One floating glass capsule with the camera docked in its middle (D10). Content runs
/// underneath it; dark glass over the feed, white everywhere else.
private struct ShellTabBar: View {
    let selected: AppTab
    let onSelect: (AppTab) -> Void
    let onCamera: () -> Void

    private var isDark: Bool { selected == .works }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.works, title: "Works", symbol: "play.rectangle.on.rectangle")
            item(.styles, title: "Styles", symbol: "paintpalette")
            CameraButton(action: onCamera)
                .frame(width: 74)
            item(.samples, title: "Samples", symbol: "sparkles.rectangle.stack")
            item(.me, title: "Me", symbol: "person.crop.circle")
        }
        .frame(height: 56)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(isDark ? Color(hex: 0x12101C).opacity(0.55) : Color.white.opacity(0.85))
                Capsule().strokeBorder(isDark ? Color.white.opacity(0.12) : Theme.Palette.hairline, lineWidth: 1)
            }
            .environment(\.colorScheme, isDark ? .dark : .light)
            .shadow(color: .black.opacity(isDark ? 0 : 0.10), radius: 13, y: 10)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.2), value: isDark)
    }

    private func item(_ tab: AppTab, title: LocalizedStringKey, symbol: String) -> some View {
        let isSelected = tab == selected
        let base = isDark ? Color.white : Theme.Palette.ink
        return Button { onSelect(tab) } label: {
            VStack(spacing: 1) {
                Image(systemName: isSelected ? symbol + ".fill" : symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 22)
                Text(title).font(.system(size: 10, weight: .bold))
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 4, height: 4)
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(isSelected ? base : base.opacity(0.45))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The raised centre button: a gradient circle that opens the camera.
private struct CameraButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.Gradients.mark)
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3)
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 60)
            .shadow(color: Theme.Palette.blue.opacity(0.45), radius: 11, y: 8)
            .offset(y: -14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Shoot"))
        .accessibilityHint(Text("Opens the camera."))
    }
}

private struct UnsupportedDeviceView: View {
    var body: some View {
        StateMessageView(
            systemImage: "iphone.slash",
            title: "This iPhone isn't supported",
            message: "AniReel needs iPhone 11, iPhone SE (2nd generation) or newer to stylize video in real time."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.surface)
    }
}
