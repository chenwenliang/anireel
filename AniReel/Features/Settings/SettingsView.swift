import SwiftUI

/// Pushed from 我的. Account actions live in 我的 itself (Phase 7), so this is capture
/// defaults, storage and about.
struct SettingsView: View {
    @Environment(PreferencesStore.self) private var preferences
    @Environment(ClipLibrary.self) private var library
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var store = preferences
        Form {
            Section {
                Picker("Default camera", selection: $store.preferences.capture.position) {
                    Text("Back").tag(CameraPosition.back)
                    Text("Front").tag(CameraPosition.front)
                }
                Toggle("Mirror front camera", isOn: $store.preferences.capture.mirrorsFront)
                Toggle("Mute by default", isOn: $store.preferences.capture.mutedByDefault)
            } header: {
                Text("Capture")
            } footer: {
                Text("Applies the next time you open the camera.")
            }

            Section {
                LabeledContent("Clips", value: "\(library.clips.count)")
                LabeledContent("Space used", value: library.index.totalBytes.formatted(.byteCount(style: .file)))
                Button("Clear My Clips", role: .destructive) { isConfirmingClear = true }
                    .disabled(library.clips.isEmpty)
            } header: {
                Text("Storage")
            } footer: {
                Text("Clearing removes AniReel's copies only. Videos in Photos are not affected.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
                NavigationLink("Privacy Policy") { LegalDocumentView(document: .privacyPolicy) }
                NavigationLink("Terms of Service") { LegalDocumentView(document: .terms) }
                Link("Send Feedback", destination: ProfileView.feedbackURL)
            } header: {
                Text("About")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.groupedBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear My Clips?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear My Clips", role: .destructive) { library.deleteAll() }
        } message: {
            Text("This removes AniReel's copies only. The videos in Photos are not affected.")
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

enum LegalDocument {
    case privacyPolicy
    case terms

    /// Localized bundle resource: Resources/<lang>.lproj/<name>.txt
    var resourceName: String {
        switch self {
        case .privacyPolicy: "PrivacyPolicy"
        case .terms: "TermsOfService"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .privacyPolicy: "Privacy Policy"
        case .terms: "Terms of Service"
        }
    }

    func text(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// The legal texts use a tiny markup: "# " title, "## " section heading, "- " bullet,
/// blank lines between paragraphs.
enum LegalBlock: Equatable {
    case title(String)
    case heading(String)
    case bullet(String)
    case paragraph(String)

    static func parse(_ text: String) -> [LegalBlock] {
        var blocks: [LegalBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("## ") {
                flush()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush()
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(LegalBlock.parse(document.text() ?? "").enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .title(let text):
                        Text(verbatim: text).font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
                    case .heading(let text):
                        Text(verbatim: text).font(Theme.Typography.headline).foregroundStyle(Theme.Palette.ink).padding(.top, 8)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: "•").foregroundStyle(Theme.accent)
                            Text(verbatim: text)
                        }
                    case .paragraph(let text):
                        Text(verbatim: text)
                    }
                }
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.gutter)
            .cardSurface()
            .padding(16)
        }
        .background(Theme.Palette.groupedBackground)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
