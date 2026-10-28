import AVFoundation
import SwiftUI

/// App-local library of saved clips: grid, play, share, delete (local copy only).
struct MyClipsView: View {
    var onShoot: (() -> Void)?
    @Environment(ClipLibrary.self) private var library
    @State private var selected: ClipRecord?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        Group {
            if library.clips.isEmpty {
                StateMessageView(
                    systemImage: "film.stack",
                    title: "No clips yet",
                    message: "Clips you record are kept here as well as in Photos."
                ) {
                    if let onShoot {
                        Button(action: onShoot) { Label("Shoot", systemImage: "camera.fill") }
                            .buttonStyle(.gradient)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(library.clips) { clip in
                            Button { selected = clip } label: {
                                ClipThumbnail(url: library.url(for: clip))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                                    .overlay(alignment: .bottomTrailing) {
                                        Text(clip.duration.clipDurationText)
                                            .font(.caption2.weight(.semibold))
                                            .monospacedDigit()
                                            .padding(4)
                                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                                            .padding(4)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(clip.accessibilityText)
                        }
                    }
                    .padding(Theme.Spacing.stack)
                }
            }
        }
        .background(Theme.Palette.groupedBackground)
        .navigationTitle("My Clips")
        .sheet(item: $selected) { clip in
            ClipDetailView(clip: clip)
        }
    }
}

private struct ClipDetailView: View {
    let clip: ClipRecord
    @Environment(ClipLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LoopingVideo(url: library.url(for: clip))
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                clip.accessibilityText
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.secondary)
                    ShareLink(item: library.url(for: clip)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.gradient)
                }
            }
            .padding(Theme.Spacing.gutter)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete this clip from My Clips?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    library.delete(clip)
                    dismiss()
                }
            } message: {
                Text("This removes AniReel's copy only. The video in Photos is not affected.")
            }
        }
    }
}

struct ClipThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(.gray.opacity(0.2))
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 240, height: 426)
                if let frame = try? await generator.image(at: .zero) {
                    image = UIImage(cgImage: frame.image)
                }
            }
    }
}

extension TimeInterval {
    var clipDurationText: String {
        let whole = Int(rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

extension ClipRecord {
    var styleTitle: String {
        StyleRegistry.shipping.pack(for: StyleID(rawValue: styleID))?.descriptor.title ?? styleID
    }

    var accessibilityText: Text {
        Text("\(styleTitle), \(duration.clipDurationText), \(createdAt.formatted(date: .abbreviated, time: .shortened))")
    }
}
