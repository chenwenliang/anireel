import SwiftUI

/// 我的, works-first (D10): identity card with stats, an inline grid of recent clips, then a
/// short list of settings, legal and feedback, then account actions. Delete Account stays here
/// rather than under Settings (D10, App Review 5.1.1(v) discoverability).
struct ProfileView: View {
    @Binding var path: [ProfileRoute]
    let onShoot: () -> Void
    @Environment(ClipLibrary.self) private var library

    /// Placeholder until a real support address exists (docs/APPSTORE.md).
    static let feedbackURL = URL(string: "mailto:feedback@anireel.app?subject=AniReel%20Feedback")!
    /// Two rows of the inline grid; the rest is one tap away in My Clips.
    private static let inlineClipCount = 6

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ProfileHeader()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    InlineClipGrid(clips: Array(library.clips.prefix(Self.inlineClipCount)), onOpen: { path = [.myClips] }, onShoot: onShoot)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("My Clips")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        if !library.clips.isEmpty {
                            Button { path = [.myClips] } label: {
                                Text("All \(library.clips.count) ›")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.secondaryInk)
                        }
                    }
                    .textCase(nil)
                }

                Section {
                    NavigationLink(value: ProfileRoute.settings) { Label("Settings", systemImage: "gearshape") }
                    NavigationLink(value: ProfileRoute.legal(.privacyPolicy)) { Label("Privacy Policy", systemImage: "hand.raised") }
                    NavigationLink(value: ProfileRoute.legal(.terms)) { Label("Terms of Service", systemImage: "doc.text") }
                    Link(destination: Self.feedbackURL) { Label("Send Feedback", systemImage: "envelope") }
                }

                AccountSection()
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.groupedBackground)
            .navigationTitle("Me")
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .myClips: MyClipsView(onShoot: onShoot)
                case .settings: SettingsView()
                case .legal(let document): LegalDocumentView(document: document)
                }
            }
        }
    }
}

private struct ProfileHeader: View {
    @Environment(AccountStore.self) private var account
    @Environment(ClipLibrary.self) private var library

    private var status: QuotaStatus {
        QuotaStatus.make(account: account.state, freeGuestRecordingsLeft: account.freeGuestRecordingsLeft)
    }

    private var stats: ProfileStats {
        ProfileStats.make(clips: library.clips, quota: status)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                BrandMark(size: 28)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    switch account.state {
                    case .guest:
                        Text("Guest").font(Theme.Typography.title)
                    case .signedIn(let signedIn):
                        Text(verbatim: signedIn.email).font(Theme.Typography.headline).lineLimit(1).truncationMode(.middle)
                    }
                    status.summary
                        .font(Theme.Typography.caption)
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                StatCell(value: Text(verbatim: "\(stats.clips)"), label: "Works")
                StatCell(value: Text(verbatim: "\(stats.thisWeek)"), label: "This week")
                switch stats.allowance {
                case .unlimited: StatCell(value: Text(verbatim: "∞"), label: "Recordings left")
                case .remaining(let left): StatCell(value: Text(verbatim: "\(left)"), label: "Recordings left")
                }
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Theme.Gradients.aurora, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .shadow(color: Theme.Palette.blue.opacity(0.25), radius: 13, y: 12)
        .accessibilityElement(children: .combine)
    }
}

private struct StatCell: View {
    let value: Text
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 1) {
            value.font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 10, weight: .semibold)).opacity(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Three-column grid of the newest clips; any tap opens the full My Clips grid.
private struct InlineClipGrid: View {
    let clips: [ClipRecord]
    let onOpen: () -> Void
    let onShoot: () -> Void
    @Environment(ClipLibrary.self) private var library

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 3)

    var body: some View {
        if clips.isEmpty {
            HStack(spacing: 12) {
                Text("No clips yet")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                Spacer()
                Button(action: onShoot) { Label("Shoot", systemImage: "camera.fill") }
                    .buttonStyle(.gradient)
                    .frame(width: 120)
            }
            .padding(14)
            .cardSurface()
        } else {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(clips) { clip in
                    Button(action: onOpen) {
                        Color.clear
                            .aspectRatio(9 / 13, contentMode: .fit)
                            .overlay { ClipThumbnail(url: library.url(for: clip)).scaledToFill() }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Text(clip.duration.clipDurationText)
                                    .font(.system(size: 10, weight: .heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 2)
                                    .padding(5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(clip.accessibilityText)
                }
            }
        }
    }
}
