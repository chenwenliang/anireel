import SwiftUI

/// Full-screen confirmation after a clip is saved: the clip loops, with Share / Retake / Done,
/// and chips that go straight back to the camera in another style (D10).
struct ResultView: View {
    /// The My Clips copy; `nil` when keeping a copy failed (the Photos copy exists regardless).
    let clip: ClipRecord?
    let library: ClipLibrary
    /// Every style other than the one just used.
    let nextStyles: [StyleDescriptor]
    let onNextStyle: (StyleID) -> Void
    let onRetake: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Theme.Palette.stage.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button("Done", action: onDone)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("result.done")
                }
                if let clip {
                    ClipSurface(url: library.url(for: clip), gravity: .resizeAspect)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Pill(text: Text(clip.styleTitle), systemImage: "sparkles").padding(12)
                        }
                        .accessibilityElement()
                        .accessibilityLabel(Text("Your new clip, playing"))
                } else {
                    Spacer()
                    BrandMark(size: 72)
                }
                VStack(spacing: 6) {
                    Label(clip == nil ? LocalizedStringKey("Saved to Photos") : "Saved to Photos · Added to My Clips", systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.multicolor)
                    if clip == nil {
                        Text("The clip is in Photos, but a copy couldn't be kept in My Clips.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                }
                if clip == nil { Spacer() }
                HStack(spacing: 12) {
                    Button(action: onRetake) {
                        Label("Retake", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.secondaryOnDark)
                    if let clip {
                        ShareLink(item: library.url(for: clip)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.gradient)
                    }
                }
                if !nextStyles.isEmpty {
                    VStack(spacing: 8) {
                        Text("Next one in another style?")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        HStack(spacing: 8) {
                            ForEach(nextStyles, id: \.id) { style in
                                Button { onNextStyle(style.id) } label: {
                                    Pill(text: Text(style.title), systemImage: "camera.fill")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Shoot in \(style.title)"))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, 12)
        }
        .onAppear {
            AccessibilityNotification.Announcement(String(localized: "Saved to Photos")).post()
        }
    }
}
