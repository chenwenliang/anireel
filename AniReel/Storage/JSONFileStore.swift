import Foundation

/// One Codable value in one file under Application Support. Plain files keep app data out of
/// UserDefaults, which would need a privacy-manifest reason.
struct JSONFileStore<Value: Codable> {
    let url: URL

    static func applicationSupport(_ relativePath: String) -> JSONFileStore {
        JSONFileStore(url: AppDirectories.applicationSupport.appendingPathComponent(relativePath))
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

enum AppDirectories {
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniReel", isDirectory: true)
    }
}
