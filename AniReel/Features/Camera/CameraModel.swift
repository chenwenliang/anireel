import Foundation
import Observation
import UIKit

/// Owns one style's live pipeline (camera → StyleEngine → preview + recorder) and runs the
/// effects that `RecordingMachine` asks for.
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

    @ObservationIgnored private let pack: any StylePack
    @ObservationIgnored private let camera = CameraSession()
    @ObservationIgnored private let recorder = ClipRecorder()
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(pack: any StylePack) {
        self.pack = pack
    }

    func start() async {
        guard await PermissionsManager.request(.camera) == .granted else {
            phase = .permissionDenied
            return
        }
        microphoneAvailable = await PermissionsManager.request(.microphone) == .granted
        do {
            let context = try MetalContext()
            let engine = try StyleEngine(pack: pack, context: context)
            let preview = try PreviewRenderer(context: context)
            camera.onFrame = { [recorder] pixelBuffer, time in
                engine.process(pixelBuffer) { stylized in
                    preview.display(stylized)
                    recorder.appendVideo(stylized, at: time)
                }
            }
            camera.onAudio = { [recorder] in recorder.appendAudio($0) }
            camera.onInterrupted = { [weak self] in Task { @MainActor in self?.interrupt() } }
            recorder.onProgress = { [weak self] elapsed in Task { @MainActor in self?.send(.progressed(elapsed)) } }
            recorder.onFailure = { [weak self] in Task { @MainActor in self?.send(.writingFailed) } }
            try await camera.start(configuration, includeAudio: microphoneAvailable)
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
        camera.stop()
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
            try await camera.apply(next)
            configuration = next
        } catch {
            try? await camera.apply(configuration)
        }
    }

    func send(_ event: RecordingEvent) {
        let (next, effects) = RecordingMachine.reduce(recording, event)
        recording = next
        updateBackgroundTask()
        effects.forEach(perform)
    }

    private func perform(_ effect: RecordingEffect) {
        switch effect {
        case .beginWriting:
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("AniReel-\(UUID().uuidString).mp4")
            do {
                try recorder.start(url: url, includeAudio: microphoneAvailable && !isMuted)
            } catch {
                send(.writingFailed)
            }
        case .finishWriting:
            recorder.finish { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let clip): self?.send(.finished(clip.url, duration: clip.duration))
                    case .failure: self?.send(.writingFailed)
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
