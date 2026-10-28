import SwiftUI

@main
struct AniReelApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(registry: .shipping, deviceTier: DeviceTier.current)
                .preferredColorScheme(.dark)
        }
    }
}
