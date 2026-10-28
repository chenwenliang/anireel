import SwiftUI

@main
struct AniReelApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(registry: .shipping, deviceTier: DeviceTier.current)
                // Light surfaces by design (D9); immersive screens draw their own dark stage.
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
    }
}
