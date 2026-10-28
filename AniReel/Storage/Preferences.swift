import Foundation
import Observation

struct CaptureDefaults: Codable, Equatable {
    var position: CameraPosition = .back
    var mirrorsFront = true
    var mutedByDefault = false

    init() {}

    /// Missing keys fall back to defaults so older files keep loading as fields are added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CaptureDefaults()
        position = try container.decodeIfPresent(CameraPosition.self, forKey: .position) ?? defaults.position
        mirrorsFront = try container.decodeIfPresent(Bool.self, forKey: .mirrorsFront) ?? defaults.mirrorsFront
        mutedByDefault = try container.decodeIfPresent(Bool.self, forKey: .mutedByDefault) ?? defaults.mutedByDefault
    }
}

struct AppPreferences: Codable, Equatable {
    var capture = CaptureDefaults()
    var hasCompletedOnboarding = false
    /// Raw `StyleID` of the style last filmed with; the camera's default style.
    var lastStyleID: String?

    var lastStyle: StyleID? {
        get { lastStyleID.map(StyleID.init(rawValue:)) }
        set { lastStyleID = newValue?.rawValue }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capture = try container.decodeIfPresent(CaptureDefaults.self, forKey: .capture) ?? CaptureDefaults()
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        lastStyleID = try container.decodeIfPresent(String.self, forKey: .lastStyleID)
    }
}

@MainActor
@Observable
final class PreferencesStore {
    var preferences: AppPreferences {
        didSet { try? file.save(preferences) }
    }

    @ObservationIgnored private let file: JSONFileStore<AppPreferences>

    init(file: JSONFileStore<AppPreferences> = .applicationSupport("preferences.json")) {
        self.file = file
        preferences = file.load() ?? AppPreferences()
    }
}
