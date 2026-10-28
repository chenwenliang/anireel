import SwiftUI

/// 作品: an immersive vertical paging feed of the user's clips, newest first; while the library
/// is empty, exactly one sample work per style (HomeFeed).
struct HomeFeedView: View {
    let samples: [SampleWork]
    let onShoot: (StyleID?) -> Void
    let onOpenMyClips: () -> Void
    let onOpenProfile: () -> Void
    @Environment(ClipLibrary.self) private var library
    @Environment(AccountStore.self) private var account
    @State private var currentID: String?
    /// Feed playback starts muted; a tap on the video turns sound on for the whole feed.
    @State private var isMuted = true
    @State private var authScreen: AuthScreen?

    private var items: [HomeFeedItem] { HomeFeed.items(clips: library.clips, samples: samples) }

    private var currentIndex: Int {
        items.firstIndex { $0.id == currentID } ?? 0
    }

    var body: some View {
        // Pages run full-bleed under the status bar and the floating tab bar; the insets read
        // here keep their overlays clear of both.
        GeometryReader { geometry in
            feed(insets: geometry.safeAreaInsets)
        }
        .sheet(item: $authScreen) { screen in
            AuthFlowView(start: screen) { authScreen = nil }
        }
    }

    private func feed(insets: EdgeInsets) -> some View {
        ZStack(alignment: .top) {
            Theme.Palette.stage.ignoresSafeArea()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        page(for: item, index: index, isActive: index == currentIndex, insets: insets)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .clipped()
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $currentID)
            .ignoresSafeArea()

            if let reel = ReelIndicator.make(count: items.count, current: currentIndex) {
                ReelStrip(indicator: reel)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 5)
                    .padding(.top, 76)
                    .animation(.snappy, value: reel)
            }

            HStack {
                Wordmark(onDark: true)
                Spacer()
                QuotaChip(status: QuotaStatus.make(account: account.state, freeGuestRecordingsLeft: account.freeGuestRecordingsLeft)) {
                    if case .guest = account.state { authScreen = .register } else { onOpenProfile() }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 4)
        }
    }

    @ViewBuilder private func page(for item: HomeFeedItem, index: Int, isActive: Bool, insets: EdgeInsets) -> some View {
        switch item {
        case .clip(let clip):
            ClipFeedPage(clip: clip, isActive: isActive, isMuted: $isMuted, insets: insets, onOpenMyClips: onOpenMyClips)
        case .sample(let sample):
            SampleFeedPage(sample: sample, position: index + 1, total: items.count, isActive: isActive, insets: insets) {
                onShoot(sample.style)
            }
        }
    }
}

/// Thin segments on the feed's right edge; the current page is the long bright one.
private struct ReelStrip: View {
    let indicator: ReelIndicator

    var body: some View {
        VStack(spacing: 4) {
            ForEach(indicator.pages, id: \.self) { page in
                Capsule()
                    .fill(.white.opacity(page == indicator.current ? 1 : 0.35))
                    .frame(width: 3, height: page == indicator.current ? 36 : 22)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
        .accessibilityHidden(true)
    }
}

private struct ClipFeedPage: View {
    let clip: ClipRecord
    let isActive: Bool
    @Binding var isMuted: Bool
    let insets: EdgeInsets
    let onOpenMyClips: () -> Void
    @Environment(ClipLibrary.self) private var library
    @State private var isConfirmingDelete = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ClipSurface(url: library.url(for: clip), isPlaying: isActive, isMuted: isMuted)
                .contentShape(Rectangle())
                .onTapGesture { isMuted.toggle() }
                .accessibilityElement()
                .accessibilityLabel(clip.accessibilityText)
                .accessibilityHint(Text("Double-tap to turn sound on or off."))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { isMuted.toggle() }
            Theme.Gradients.scrimBottom.frame(height: 300 + insets.bottom).allowsHitTesting(false)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Pill(text: Text(clip.styleTitle), systemImage: "sparkles", tone: .accent)
                    Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Typography.headline)
                    Label(clip.duration.clipDurationText, systemImage: "clock")
                        .font(Theme.Typography.caption)
                        .monospacedDigit()
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .accessibilityElement(children: .combine)
                Spacer()
                VStack(spacing: 18) {
                    FeedAction(systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: isMuted ? "Sound off" : "Sound on") {
                        isMuted.toggle()
                    }
                    ShareLink(item: library.url(for: clip)) {
                        FeedActionLabel(systemImage: "arrowshape.turn.up.right.fill", title: "Share")
                    }
                    FeedAction(systemImage: "square.grid.2x2.fill", title: "My Clips", action: onOpenMyClips)
                    FeedAction(systemImage: "trash.fill", title: "Delete") { isConfirmingDelete = true }
                }
            }
            .padding(.leading, Theme.Spacing.gutter)
            .padding(.trailing, 12)
            .padding(.bottom, insets.bottom + 16)
        }
        .overlay(alignment: .top) {
            Theme.Gradients.scrimTop.frame(height: insets.top + 80).allowsHitTesting(false)
        }
        .confirmationDialog("Delete this clip from My Clips?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { library.delete(clip) }
        } message: {
            Text("This removes AniReel's copy only. The video in Photos is not affected.")
        }
    }
}

/// Samples must never pass for the user's own clips: coral corner ribbon, glass card, and a
/// line saying the art is illustrative (D10).
private struct SampleFeedPage: View {
    let sample: SampleWork
    let position: Int
    let total: Int
    let isActive: Bool
    let insets: EdgeInsets
    let onShoot: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var descriptor: StyleDescriptor? { StyleRegistry.shipping.pack(for: sample.style)?.descriptor }

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geometry in
                StyleCover(style: sample.style)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    // A slow drift keeps the still cover from feeling dead.
                    .phaseAnimator(reduceMotion || !isActive ? [1.0] : [1.0, 1.08]) { cover, scale in
                        cover.scaleEffect(scale)
                    } animation: { _ in .easeInOut(duration: 7) }
                    .clipped()
            }
            Theme.Gradients.scrimBottom.frame(height: 380 + insets.bottom).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                Pill(text: Text("Sample \(position) / \(total)"), systemImage: "sparkles", tone: .accent)
                Text(descriptor?.title ?? sample.style.rawValue)
                    .font(Theme.Typography.title)
                Text(sample.explanation)
                    .font(Theme.Typography.caption)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onShoot) {
                    Label("Shoot one in this style", systemImage: "camera.fill")
                }
                .buttonStyle(.gradient)
                .padding(.top, 6)
                Text("Samples illustrate each style. Your clip looks like the live preview.")
                    .font(.system(size: 10))
                    .opacity(0.6)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, insets.bottom + 12)
        }
        .overlay(alignment: .top) {
            Theme.Gradients.scrimTop.frame(height: insets.top + 80).allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            SampleRibbon().offset(x: -46, y: insets.top + 64)
        }
    }
}

private struct SampleRibbon: View {
    var body: some View {
        Text("Sample work")
            .font(.system(size: 11, weight: .heavy))
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.vertical, 5)
            .frame(width: 170)
            .background(Theme.accent)
            .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
            .rotationEffect(.degrees(-45))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct FeedAction: View {
    let systemImage: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FeedActionLabel(systemImage: systemImage, title: title)
        }
        .buttonStyle(.plain)
    }
}

private struct FeedActionLabel: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
            Text(title).font(.system(size: 10, weight: .bold))
                .shadow(color: .black.opacity(0.4), radius: 2)
        }
        .foregroundStyle(.white)
        .frame(minWidth: 52)
        .accessibilityElement(children: .combine)
    }
}

/// Guest allowance or account state; the top-right chip of the feed.
struct QuotaChip: View {
    let status: QuotaStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch status {
            case .guestFree(let left):
                Pill(text: Text("Free recordings left: \(left)"), systemImage: "gift.fill")
            case .guestUsedUp:
                Pill(text: Text("Free recording used · Sign up"), systemImage: "person.badge.plus", tone: .accent)
            case .signedIn:
                Pill(text: Text("Signed in · Unlimited"), systemImage: "checkmark.seal.fill")
            }
        }
        .buttonStyle(.plain)
    }
}

extension QuotaStatus {
    /// One-line description for the profile header.
    var summary: Text {
        switch self {
        case .guestFree(let left): Text("Free recordings left: \(left)")
        case .guestUsedUp: Text("You've used your free recording. Create a free account to keep recording.")
        case .signedIn: Text("Unlimited recordings.")
        }
    }
}
