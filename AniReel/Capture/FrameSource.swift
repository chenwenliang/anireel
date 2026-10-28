import AVFoundation

/// Where stylized frames come from. Both sources feed the same StyleEngine → preview + recorder path.
protocol FrameSource: AnyObject, Sendable {
    var onFrame: (@Sendable (CVPixelBuffer, CMTime) -> Void)? { get set }
    var onAudio: (@Sendable (CMSampleBuffer) -> Void)? { get set }
    var onInterrupted: (@Sendable () -> Void)? { get set }
    var requiresCameraPermission: Bool { get }

    func start(_ configuration: CameraConfiguration) async throws
    func apply(_ configuration: CameraConfiguration) async throws
    /// Returns whether microphone audio is now flowing to `onAudio`.
    func setAudioCapture(_ enabled: Bool) async -> Bool
    /// Whether the active camera has a usable torch (never for the front camera or demo frames).
    func isTorchAvailable() async -> Bool
    /// Returns the torch state actually applied.
    func setTorch(_ on: Bool) async -> Bool
    func stop()
}

enum FrameSourceKind: Equatable {
    case camera
    /// Synthetic frames for the Simulator and camera-less hardware (docs/DECISIONS.md D4).
    case demo

    static func select(isSimulator: Bool, hasCamera: Bool) -> FrameSourceKind {
        isSimulator || !hasCamera ? .demo : .camera
    }

    static var current: FrameSourceKind {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return select(isSimulator: isSimulator, hasCamera: AVCaptureDevice.default(for: .video) != nil)
    }

    func makeSource() -> any FrameSource {
        switch self {
        case .camera: CameraSession()
        case .demo: DemoFrameSource()
        }
    }
}
