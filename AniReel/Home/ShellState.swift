/// The app's one navigation model (D9): a bottom tab shell plus the camera presented over it.
/// The centre button is not a tab; it opens the camera.
enum AppTab: Hashable, CaseIterable {
    case works
    case styles
    case samples
    case me
}

/// Screens pushed inside the 我的 tab.
enum ProfileRoute: Hashable {
    case myClips
    case settings
    case legal(LegalDocument)
}

struct CameraRoute: Identifiable, Equatable {
    let style: StyleID
    var id: String { style.rawValue }
}

/// Pure routing state for the shell; views only call these transitions.
struct ShellState: Equatable {
    var tab: AppTab = .works
    var camera: CameraRoute?
    var profilePath: [ProfileRoute] = []

    /// Opens the camera on `style`, or on the last-used style, or the first available.
    mutating func openCamera(style: StyleID?, lastUsed: StyleID?, available: [StyleID]) {
        guard let resolved = StyleChoice.resolve(requested: style, lastUsed: lastUsed, available: available) else { return }
        camera = CameraRoute(style: resolved)
    }

    mutating func closeCamera() {
        camera = nil
    }

    /// The result screen's Done: back to the feed, where the new clip is now first.
    mutating func finishCapture() {
        camera = nil
        tab = .works
    }

    /// From the feed or the camera's latest-clip thumbnail: the My Clips grid in 我的.
    mutating func openMyClips() {
        camera = nil
        tab = .me
        profilePath = [.myClips]
    }

    mutating func select(_ next: AppTab) {
        // Re-tapping 我的 pops back to its root, as system tab bars do.
        if next == tab, next == .me { profilePath = [] }
        tab = next
    }
}
