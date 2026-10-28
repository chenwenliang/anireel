import AVFoundation

enum CameraError: Error {
    case noCamera
    case cannotAddInput
    case cannotAddOutput
}

enum CameraPosition {
    case back
    case front

    var device: AVCaptureDevice.Position {
        switch self {
        case .back: .back
        case .front: .front
        }
    }

    var toggled: CameraPosition { self == .back ? .front : .back }
}

struct CameraConfiguration: Equatable {
    var position: CameraPosition = .back
    var mirrorsFront = true

    /// Mirroring is applied on the capture connection, so preview and recording get the same pixels.
    var isMirrored: Bool { position == .front && mirrorsFront }
}

/// Camera capture delivering portrait 30 fps BGRA frames, plus mic sample buffers while audio
/// capture is enabled. All session work runs on `sessionQueue`. Set the callbacks before `start`.
final class CameraSession: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable
{
    var onFrame: (@Sendable (CVPixelBuffer, CMTime) -> Void)?
    var onAudio: (@Sendable (CMSampleBuffer) -> Void)?
    /// Calls, Siri, another app taking the camera, runtime errors.
    var onInterrupted: (@Sendable () -> Void)?
    let requiresCameraPermission = true

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.anireel.camera.session")
    private let videoQueue = DispatchQueue(label: "com.anireel.camera.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.anireel.camera.audio")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var micInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        session.automaticallyConfiguresApplicationAudioSession = false
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.onInterrupted?()
            })
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start(_ configuration: CameraConfiguration) async throws {
        try await onSessionQueue { [self] in
            if !isConfigured {
                try configure(configuration)
                isConfigured = true
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func apply(_ configuration: CameraConfiguration) async throws {
        try await onSessionQueue { [self] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            try applyVideo(configuration)
        }
    }

    func setAudioCapture(_ enabled: Bool) async -> Bool {
        (try? await onSessionQueue { [self] in configureAudio(enabled) }) ?? false
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func onSessionQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            sessionQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure(_ configuration: CameraConfiguration) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        try applyVideo(configuration)
    }

    /// Audio is best effort: a missing or busy mic means a silent clip, never a blocked recording.
    private func configureAudio(_ enabled: Bool) -> Bool {
        guard enabled else {
            if let micInput {
                session.beginConfiguration()
                session.removeInput(micInput)
                session.commitConfiguration()
                self.micInput = nil
            }
            return false
        }
        if micInput != nil { return true }
        guard let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic)
        else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        if !session.outputs.contains(audioOutput) {
            guard session.canAddOutput(audioOutput) else {
                session.removeInput(input)
                return false
            }
            audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
            session.addOutput(audioOutput)
        }
        micInput = input
        return true
    }

    /// Call inside begin/commitConfiguration.
    private func applyVideo(_ configuration: CameraConfiguration) throws {
        if videoInput?.device.position != configuration.position.device {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: configuration.position.device) else {
                throw CameraError.noCamera
            }
            let input = try AVCaptureDeviceInput(device: device)
            if let old = videoInput { session.removeInput(old) }
            guard session.canAddInput(input) else {
                if let old = videoInput { session.addInput(old) }
                throw CameraError.cannotAddInput
            }
            session.addInput(input)
            videoInput = input
            try lockFrameRate(device)
        }
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = configuration.isMirrored
        }
    }

    private func lockFrameRate(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        let frame = CMTime(value: 1, timescale: 30)
        device.activeVideoMinFrameDuration = frame
        device.activeVideoMaxFrameDuration = frame
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput {
            onAudio?(sampleBuffer)
        } else if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
    }
}
