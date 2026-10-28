import SwiftUI

@main
struct AniReelApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(registry: .shipping)
                .preferredColorScheme(.dark)
        }
    }
}
