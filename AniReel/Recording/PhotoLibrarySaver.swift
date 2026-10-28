import Photos

enum PhotoLibrarySaverError: Error {
    case notAuthorized
}

/// Add-only access (D5): clips go to the main library, and the app never reads the user's photos.
enum PhotoLibrarySaver {
    static func save(videoAt url: URL) async throws {
        guard await PermissionsManager.request(.photoLibraryAdd) == .granted else {
            throw PhotoLibrarySaverError.notAuthorized
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
