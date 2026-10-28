import SwiftUI

/// Full-screen confirmation after a clip is saved: the clip loops, with Share / Retake / Done.
struct ResultView: View {
    /// The My Clips copy; `nil` when keeping a copy failed (the Photos copy exists regardless).
    let clip: ClipRecord?
    let library: ClipLibrary
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
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, 12)
        }
        .onAppear {
            AccessibilityNotification.Announcement(String(localized: "Saved to Photos")).post()
        }
    }
}
