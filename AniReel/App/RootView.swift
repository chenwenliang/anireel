import SwiftUI

struct RootView: View {
    let registry: StyleRegistry
    /// `nil` means the device is below the A13 floor (docs/DECISIONS.md D1).
    let deviceTier: DeviceTier?
    @State private var path: [StyleID] = []

    var body: some View {
        if deviceTier == nil {
            UnsupportedDeviceView()
        } else {
            NavigationStack(path: $path) {
                StylePickerView(packs: registry.packs) { path.append($0) }
                    .navigationDestination(for: StyleID.self) { id in
                        if let pack = registry.pack(for: id) {
                            CameraScreen(pack: pack)
                        }
                    }
            }
        }
    }
}

private struct UnsupportedDeviceView: View {
    var body: some View {
        ContentUnavailableView {
            Label("This iPhone isn't supported", systemImage: "iphone.slash")
        } description: {
            Text("AniReel needs iPhone 11, iPhone SE (2nd generation) or newer to stylize video in real time.")
        }
    }
}
