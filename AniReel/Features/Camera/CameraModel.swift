import Foundation
import Observation
import UIKit

/// Owns the live pipeline (frame source → StyleEngine → preview + recorder), switches the live
/// style while idle, and runs the effects that `RecordingMachine` asks for.
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
    /// Set when a guest has used the free recording; the screen presents sign-up / log-in.
    var isAccountRequired = false
    var isSelfTimerOn = false
    /// Seconds left on the self-timer; `nil` when no countdown is running.
    private(set) var countdown: Int?
    private(set) var isTorchAvailable = false
    private(set) var isTorchOn = false
    /// The library copy of the clip just saved, shown on the result screen; `nil` if the copy failed.
    private(set) var savedClip: ClipRecord?
    /// The live style; changes only while idle (`RecordingPhase.allowsStyleChange`).
    private(set) var styleID: StyleID
    /// The live style's model; `nil` before the pipeline starts.
    private(set) var modelStatus: StyleModelStatus?
    let isDemo: Bool
    let packs: [any StylePack]

    @ObservationIgnored private var engine: StyleEngine?
    @ObservationIgnored private var liveRenderer: CoreMLStyleRenderer?
    @ObservationIgnored private var metal: MetalContext?
    /// The style a clip was started in, so a saved clip is labelled correctly.
    @ObservationIgnored private var recordingStyleID: StyleID?
    @ObservationIgnored private let account: AccountStore
    let library: ClipLibrary
    @ObservationIgnored private let source: any FrameSource
    @ObservationIgnored private let recorder = ClipRecorder()
    @ObservationIgnored private var clipURL: URL?
    @ObservationIgnored private var clipDuration: TimeInterval = 0
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var isRecordingAudio = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(
        packs: [any StylePack],
        style: StyleID,
        account: AccountStore,
        library: ClipLibrary,
        defaults: CaptureDefaults,
        sourceKind: FrameSourceKind = .current
    ) {
        self.packs = packs
        self.styleID = style
        self.account = account
        self.library = library
        self.source = sourceKind.makeSource()
        self.isDemo = sourceKind == .demo
        configuration = CameraConfiguration(position: defaults.position, mirrorsFront: defaults.mirrorsFront)
        isMuted = defaults.mutedByDefault
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
            let engine = try StyleEngine(renderer: makeRenderer(for: pack, context: context), context: context)
            self.engine = engine
            metal = context
            let preview = try PreviewRenderer(context: context)
            source.onFrame = { [recorder] pixelBuffer, time in
                engine.process(pixelBuffer) { frame, isStylized in
                    preview.display(frame, original: pixelBuffer)
                    // Only model output is ever written; placeholder frames are preview-only.
                    if isStylized { recorder.appendVideo(frame, at: time) }
                }
            }
            source.onAudio = { [recorder] in recorder.appendAudio($0) }
            source.onInterrupted = { [weak self] in Task { @MainActor in self?.interrupt() } }
            recorder.onProgress = { [weak self] elapsed in Task { @MainActor in self?.send(.progressed(elapsed)) } }
            recorder.onFailure = { [weak self] in Task { @MainActor in self?.send(.writingFailed) } }
            try await source.start(configuration)
            isTorchAvailable = await source.isTorchAvailable()
            phase = .running(preview, context)
        } catch {
            phase = .failed
        }
    }

    var pack: any StylePack {
        packs.first { $0.descriptor.id == styleID } ?? packs[0]
    }

    var canChangeStyle: Bool { recording.allowsStyleChange && countdown == nil }

    /// Switches the live style. Ignored mid-clip or during a countdown; if the new renderer
    /// cannot be built the previous style stays live.
    func selectStyle(_ id: StyleID) {
        guard canChangeStyle, id != styleID,
              let next = packs.first(where: { $0.descriptor.id == id })
        else { return }
        if let engine, let metal {
            guard let renderer = try? makeRenderer(for: next, context: metal) else { return }
            engine.setRenderer(renderer)
        }
        styleID = id
    }

    /// Model loading happens later on the video queue (and once per process), so this is cheap
    /// enough for the main thread.
    private func makeRenderer(for pack: any StylePack, context: MetalContext) throws -> StyleRenderer {
        let renderer = try pack.makeRenderer(context: context)
        let ml = renderer as? CoreMLStyleRenderer
        liveRenderer = ml
        modelStatus = ml?.initialStatus
        ml?.onStatus = { [weak self, weak ml] status in
            Task { @MainActor in
                guard let self, let ml, self.liveRenderer === ml else { return }
                self.modelStatusChanged(status)
            }
        }
        return renderer
    }

    private func modelStatusChanged(_ status: StyleModelStatus) {
        modelStatus = status
        // Frames after a failure are not recorded; end the clip and keep what was stylized.
        guard !status.allowsRecording else { return }
        cancelCountdown()
        if isRecording { send(.stopRequested) }
    }

    /// The model size the next tap on the status badge switches to; `nil` when there is no choice.
    var nextInferenceSide: Int? {
        guard case .running(let stats) = modelStatus, canChangeStyle, let liveRenderer,
              liveRenderer.availableSides.count > 1
        else { return nil }
        return InferenceGovernor.nextSide(after: stats.side, available: Set(liveRenderer.availableSides))
    }

    /// Measures another model size (POC: 512 vs 384). Only while idle, like a style change.
    func cycleInferenceSide() {
        guard let side = nextInferenceSide else { return }
        liveRenderer?.requestSide(side)
        modelStatus = .loading
    }

    /// The record button: cancels a countdown, stops a running clip, or starts one if the
    /// recording gate allows it.
    func recordButtonTapped() {
        if countdown != nil {
            cancelCountdown()
            return
        }
        if isRecording {
            send(.stopRequested)
            return
        }
        guard canRecordStyle else { return }
        begin(CaptureStart.plan(decision: account.recordingDecision, selfTimer: isSelfTimerOn))
    }

    /// A clip can only start while the style's model is producing frames.
    var canRecordStyle: Bool { modelStatus?.allowsRecording ?? true }

    /// Called after sign-up or log-in from the gate: the recording the guest asked for starts now.
    func accountProvided() {
        isAccountRequired = false
        begin(CaptureStart.plan(decision: account.recordingDecision, selfTimer: isSelfTimerOn))
    }

    private func begin(_ plan: CaptureStart) {
        switch plan {
        case .startNow:
            send(.startRequested)
        case .requireAccount:
            isAccountRequired = true
        case .countdown(let seconds):
            countdownTask = Task {
                for remaining in stride(from: seconds, to: 0, by: -1) {
                    countdown = remaining
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
                countdown = nil
                if canRecordStyle { send(.startRequested) }
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    /// Leaving the screen or the app ends a recording and keeps what was filmed.
    func interrupt() {
        cancelCountdown()
        send(.stopRequested)
    }

    func toggleTorch() async {
        isTorchOn = await source.setTorch(!isTorchOn)
    }

    /// Closes the result screen; the camera is ready for the next clip.
    func dismissResult() {
        savedClip = nil
        send(.acknowledged)
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
        isTorchOn = false
        isTorchAvailable = await source.isTorchAvailable()
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
            recordingStyleID = styleID
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
                        self?.clipDuration = clip.duration
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
        case .clipSaved(let url):
            account.noteClipSaved()
            savedClip = try? library.importClip(from: url, duration: clipDuration, styleID: recordingStyleID ?? styleID)
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
