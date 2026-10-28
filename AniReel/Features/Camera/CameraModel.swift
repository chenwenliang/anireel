import Foundation
import Observation
import UIKit

/// Owns one style's live pipeline (frame source → StyleEngine → preview + recorder) and runs
/// the effects that `RecordingMachine` asks for.
@MainActor
@Observable
final class CameraModel {
    enum Phase {
        case starting
        case permissionDenied
        case running(PreviewRenderer, MetalContext)
        case failed
    }

    private(set) var phase: Phase = .starting
    private(set) var recording: RecordingPhase = .ready
    private(set) var configuration = CameraConfiguration()
    private(set) var microphoneAvailable = false
    var isMuted = false
    let isDemo: Bool

    @ObservationIgnored private let pack: any StylePack
    @ObservationIgnored private let source: any FrameSource
    @ObservationIgnored private let recorder = ClipRecorder()
    @ObservationIgnored private var clipURL: URL?
    @ObservationIgnored private var isRecordingAudio = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(pack: any StylePack, sourceKind: FrameSourceKind = .current) {
        self.pack = pack
        self.source = sourceKind.makeSource()
        self.isDemo = sourceKind == .demo
    }

    func start() async {
        phase = .starting
        if source.requiresCameraPermission {
            guard await PermissionsManager.request(.camera) == .granted else {
                phase = .permissionDenied
                return
            }
            microphoneAvailable = await PermissionsManager.request(.microphone) == .granted
        }
        try? AudioSessionPolicy.preview.apply()
        do {
            let context = try MetalContext()
            let engine = try StyleEngine(pack: pack, context: context)
            let preview = try PreviewRenderer(context: context)
            source.onFrame = { [recorder] pixelBuffer, time in
                engine.process(pixelBuffer) { stylized in
                    preview.display(stylized)
                    recorder.appendVideo(stylized, at: time)
                }
            }
            source.onAudio = { [recorder] in recorder.appendAudio($0) }
            source.onInterrupted = { [weak self] in Task { @MainActor in self?.interrupt() } }
            recorder.onProgress = { [weak self] elapsed in Task { @MainActor in self?.send(.progressed(elapsed)) } }
            recorder.onFailure = { [weak self] in Task { @MainActor in self?.send(.writingFailed) } }
            try await source.start(configuration)
            phase = .running(preview, context)
        } catch {
            phase = .failed
        }
    }

    /// Leaving the screen or the app ends a recording and keeps what was filmed.
    func interrupt() {
        send(.stopRequested)
    }

    func stop() {
        interrupt()
        source.stop()
    }

    func toggleCamera() async {
        await apply { $0.position = $0.position.toggled }
    }

    func toggleMirroring() async {
        await apply { $0.mirrorsFront.toggle() }
    }

    private func apply(_ change: (inout CameraConfiguration) -> Void) async {
        guard !recording.isBusy else { return }
        var next = configuration
        change(&next)
        do {
            try await source.apply(next)
            configuration = next
        } catch {
            try? await source.apply(configuration)
        }
    }

    func send(_ event: RecordingEvent) {
        let (next, effects) = RecordingMachine.reduce(recording, event)
        recording = next
        updateBackgroundTask()
        if isRecordingAudio, !isRecording {
            isRecordingAudio = false
            Task { await restorePreviewAudio() }
        }
        effects.forEach(perform)
    }

    private var isRecording: Bool {
        if case .recording = recording { true } else { false }
    }

    private func perform(_ effect: RecordingEffect) {
        switch effect {
        case .beginWriting:
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("AniReel-\(UUID().uuidString).mp4")
            clipURL = url
            let wantsAudio = microphoneAvailable && !isMuted
            Task {
                let hasAudio = wantsAudio ? await startRecordingAudio() : false
                // A stop that arrived while the mic was coming up already finished this clip as empty.
                guard isRecording else {
                    if hasAudio { await restorePreviewAudio() }
                    return
                }
                isRecordingAudio = hasAudio
                do {
                    try recorder.start(url: url, includeAudio: hasAudio)
                } catch {
                    send(.writingFailed)
                }
            }
        case .finishWriting:
            let url = clipURL
            recorder.finish { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let clip):
                        self?.send(.finished(clip.url, duration: clip.duration))
                    case .failure(let error):
                        // Stopped before the recorder opened: an empty clip, handled as too short.
                        if let url, (error as? ClipRecorderError) == .notRecording {
                            self?.send(.finished(url, duration: 0))
                        } else {
                            self?.send(.writingFailed)
                        }
                    }
                }
            }
        case .save(let url):
            Task {
                do {
                    try await PhotoLibrarySaver.save(videoAt: url)
                    send(.saveSucceeded)
                } catch {
                    send(.saveFailed)
                }
            }
        case .deleteFile(let url):
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Switches to a record-capable audio session and attaches the mic. Any failure means a silent clip.
    private func startRecordingAudio() async -> Bool {
        do {
            try AudioSessionPolicy.recording.apply()
        } catch {
            return false
        }
        if await source.setAudioCapture(true) { return true }
        try? AudioSessionPolicy.preview.apply()
        return false
    }

    /// Detaches the mic first so deactivation is not refused while audio I/O is running,
    /// then lets other apps' audio resume.
    private func restorePreviewAudio() async {
        _ = await source.setAudioCapture(false)
        try? AudioSessionPolicy.preview.apply()
    }

    /// Keeps the app alive long enough to finish and save a clip after it is sent to the background.
    private func updateBackgroundTask() {
        if recording.isBusy, backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish clip") { [weak self] in
                Task { @MainActor in self?.endBackgroundTask() }
            }
        } else if !recording.isBusy {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
