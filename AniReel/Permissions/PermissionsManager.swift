import AVFoundation
import Photos
import SwiftUI

enum PermissionKind {
    case camera
    case microphone
    case photoLibraryAdd
}

enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

/// Single place that maps each system authorization API onto `PermissionStatus`.
enum PermissionsManager {
    static func status(of kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .camera: map(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photoLibraryAdd: map(PHPhotoLibrary.authorizationStatus(for: .addOnly))
        }
    }

    /// Prompts only when the user has not decided yet; otherwise returns the stored decision.
    static func request(_ kind: PermissionKind) async -> PermissionStatus {
        guard status(of: kind) == .notDetermined else { return status(of: kind) }
        switch kind {
        case .camera: return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        case .microphone: return await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        case .photoLibraryAdd: return await map(PHPhotoLibrary.requestAuthorization(for: .addOnly))
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .limited: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

struct PermissionDeniedView: View {
    let kind: PermissionKind
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text("Allow access in Settings to continue.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .camera: "Camera access is off"
        case .microphone: "Microphone access is off"
        case .photoLibraryAdd: "Photo library access is off"
        }
    }

    private var symbol: String {
        switch kind {
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        case .photoLibraryAdd: "photo.on.rectangle"
        }
    }
}
