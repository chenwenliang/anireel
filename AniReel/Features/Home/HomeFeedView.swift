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

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Palette.stage.ignoresSafeArea()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        page(for: item, isActive: item.id == (currentID ?? items.first?.id))
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $currentID)
            .ignoresSafeArea(edges: .top)

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
        .sheet(item: $authScreen) { screen in
            AuthFlowView(start: screen) { authScreen = nil }
        }
    }

    @ViewBuilder private func page(for item: HomeFeedItem, isActive: Bool) -> some View {
        switch item {
        case .clip(let clip):
            ClipFeedPage(clip: clip, isActive: isActive, isMuted: $isMuted, onOpenMyClips: onOpenMyClips)
        case .sample(let sample):
            SampleFeedPage(sample: sample, isActive: isActive) { onShoot(sample.style) }
        }
    }
}

private struct ClipFeedPage: View {
    let clip: ClipRecord
    let isActive: Bool
    @Binding var isMuted: Bool
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
            Theme.Gradients.scrimBottom.frame(height: 260).allowsHitTesting(false)
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
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, 24)
        }
        .confirmationDialog("Delete this clip from My Clips?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { library.delete(clip) }
        } message: {
            Text("This removes AniReel's copy only. The video in Photos is not affected.")
        }
    }
}

private struct SampleFeedPage: View {
    let sample: SampleWork
    let isActive: Bool
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
            Theme.Gradients.scrimBottom.frame(height: 360).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 10) {
                Pill(text: Text("Sample work"), systemImage: "sparkles", tone: .accent)
                Text(descriptor?.title ?? sample.style.rawValue)
                    .font(Theme.Typography.display)
                Text(descriptor?.subtitle ?? "")
                    .font(Theme.Typography.body)
                    .opacity(0.85)
                Text("Samples illustrate each style. Your clip looks like the live preview.")
                    .font(Theme.Typography.caption)
                    .opacity(0.6)
                Button(action: onShoot) {
                    Label("Shoot one in this style", systemImage: "camera.fill")
                }
                .buttonStyle(.gradient)
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, 28)
        }
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
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .shadow(color: .black.opacity(0.35), radius: 4)
            Text(title).font(.caption2.weight(.semibold))
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
