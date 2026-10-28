import SwiftUI

/// 我的: account header with quota, My Clips, Settings, legal, feedback, account actions.
struct ProfileView: View {
    @Binding var path: [ProfileRoute]
    let onShoot: () -> Void
    @Environment(ClipLibrary.self) private var library

    /// Placeholder until a real support address exists (docs/APPSTORE.md).
    static let feedbackURL = URL(string: "mailto:feedback@anireel.app?subject=AniReel%20Feedback")!

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ProfileHeader()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink(value: ProfileRoute.myClips) {
                        HStack {
                            Label("My Clips", systemImage: "square.grid.2x2")
                            Spacer()
                            Text(verbatim: "\(library.clips.count)")
                                .foregroundStyle(Theme.Palette.secondaryInk)
                                .monospacedDigit()
                        }
                    }
                    if !library.clips.isEmpty {
                        RecentClipsStrip(clips: Array(library.clips.prefix(4))) { path = [.myClips] }
                    }
                }

                AccountSection()

                Section {
                    NavigationLink(value: ProfileRoute.settings) { Label("Settings", systemImage: "gearshape") }
                    NavigationLink(value: ProfileRoute.legal(.privacyPolicy)) { Label("Privacy Policy", systemImage: "hand.raised") }
                    NavigationLink(value: ProfileRoute.legal(.terms)) { Label("Terms of Service", systemImage: "doc.text") }
                    Link(destination: Self.feedbackURL) { Label("Send Feedback", systemImage: "envelope") }
                }
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

    private var status: QuotaStatus {
        QuotaStatus.make(account: account.state, freeGuestRecordingsLeft: account.freeGuestRecordingsLeft)
    }

    var body: some View {
        HStack(spacing: 16) {
            BrandMark(size: 34)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
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
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.Gradients.aurora, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RecentClipsStrip: View {
    let clips: [ClipRecord]
    let onOpen: () -> Void
    @Environment(ClipLibrary.self) private var library

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                ForEach(clips) { clip in
                    ClipThumbnail(url: library.url(for: clip))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                ForEach(clips.count..<4, id: \.self) { _ in
                    Color.clear.aspectRatio(9 / 16, contentMode: .fit)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("My Clips"))
    }
}
