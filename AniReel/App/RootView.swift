import SwiftUI

struct RootView: View {
    let registry: StyleRegistry
    @State private var path: [StyleID] = []

    var body: some View {
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
