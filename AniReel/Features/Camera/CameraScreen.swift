import SwiftUI

struct CameraScreen: View {
    let pack: any StylePack
    @State private var model: CameraModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(pack: any StylePack) {
        self.pack = pack
        _model = State(initialValue: CameraModel(pack: pack))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .starting:
                ProgressView().tint(.white)
                    .accessibilityLabel(Text("Starting camera"))
            case .permissionDenied:
                PermissionDeniedView(kind: .camera)
            case .running(let preview, let context):
                MetalPreview(renderer: preview, device: context.device)
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel(Text("Live preview in \(pack.descriptor.title) style"))
                    .accessibilityAddTraits(.isImage)
                RecordingControls(model: model)
            case .failed:
                ContentUnavailableView {
                    Label("Camera unavailable", systemImage: "camera.badge.ellipsis")
                } description: {
                    Text("Another app may be using the camera. Close it and try again.")
                } actions: {
                    Button("Try Again") { Task { await model.start() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(pack.descriptor.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.recording.isBusy)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { model.interrupt() }
        }
        .alert("Clip too short", isPresented: isShowing(.tooShort)) {
            Button("Retake") { model.send(.acknowledged) }
        } message: {
            Text("Record at least 1 second.")
        }
        .alert("Recording failed", isPresented: isShowing(.recordingFailed)) {
            Button("OK") { model.send(.acknowledged) }
        }
        .alert("Couldn't save the clip", isPresented: isShowingSaveFailure) {
            Button("Retry") { model.send(.retryRequested) }
            if PermissionsManager.status(of: .photoLibraryAdd) == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("Discard", role: .destructive) { model.send(.discardRequested) }
        } message: {
            Text("The clip is kept on this device until it is saved or discarded.")
        }
    }

    private func isShowing(_ phase: RecordingPhase) -> Binding<Bool> {
        Binding(get: { model.recording == phase }, set: { _ in })
    }

    private var isShowingSaveFailure: Binding<Bool> {
        Binding(get: { if case .saveFailed = model.recording { true } else { false } }, set: { _ in })
    }
}

private struct RecordingControls: View {
    let model: CameraModel

    private var elapsed: TimeInterval {
        if case .recording(let elapsed) = model.recording { elapsed } else { 0 }
    }

    private var isRecording: Bool {
        if case .recording = model.recording { true } else { false }
    }

    var body: some View {
        VStack {
            ZStack {
                if model.isDemo {
                    DemoBadge().frame(maxWidth: .infinity, alignment: .leading)
                }
                TimerBadge(elapsed: elapsed)
                    .opacity(isRecording ? 1 : 0)
                    .accessibilityHidden(!isRecording)
            }
            .padding(.top, 8)
            Spacer()
            if model.recording == .saved {
                Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .transition(.opacity)
                    .padding(.bottom, 16)
            }
            HStack {
                muteButton
                    .opacity(model.isDemo ? 0 : 1)
                    .accessibilityHidden(model.isDemo)
                    .frame(maxWidth: .infinity)
                RecordButton(isRecording: isRecording, progress: elapsed / DurationGuard.limit) {
                    model.send(isRecording ? .stopRequested : .startRequested)
                }
                .disabled(!(isRecording || model.recording == .ready))
                cameraButtons.frame(maxWidth: .infinity)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 16)
        .animation(.default, value: model.recording)
        .task(id: model.recording == .saved) {
            guard model.recording == .saved else { return }
            AccessibilityNotification.Announcement(String(localized: "Saved to Photos")).post()
            try? await Task.sleep(for: .seconds(1.5))
            model.send(.acknowledged)
        }
    }

    private var muteButton: some View {
        let silent = model.isMuted || !model.microphoneAvailable
        return CircleIconButton(systemName: silent ? "mic.slash.fill" : "mic.fill") {
            model.isMuted.toggle()
        }
        .disabled(model.recording.isBusy || !model.microphoneAvailable)
        .accessibilityLabel(model.microphoneAvailable ? Text(model.isMuted ? LocalizedStringKey("Unmute") : "Mute") : Text("Microphone access is off"))
    }

    private var cameraButtons: some View {
        HStack(spacing: 12) {
            if model.configuration.position == .front {
                CircleIconButton(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    Task { await model.toggleMirroring() }
                }
                .opacity(model.configuration.mirrorsFront ? 1 : 0.5)
                .accessibilityLabel(Text("Mirror"))
                .accessibilityValue(Text(model.configuration.mirrorsFront ? LocalizedStringKey("On") : "Off"))
            }
            CircleIconButton(systemName: "arrow.triangle.2.circlepath.camera") {
                Task { await model.toggleCamera() }
            }
            .accessibilityLabel(Text("Switch camera"))
        }
        .disabled(model.recording.isBusy)
    }
}

private struct TimerBadge: View {
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(format(elapsed)).monospacedDigit()
            Text("-" + format(DurationGuard.limit - elapsed)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Recording, \(format(elapsed)) recorded, \(format(DurationGuard.limit - elapsed)) left"))
    }

    private func format(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

private struct RecordButton: View {
    let isRecording: Bool
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(.white.opacity(0.35), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: isRecording ? 8 : 32)
                    .fill(.red)
                    .frame(width: isRecording ? 32 : 64, height: isRecording ? 32 : 64)
            }
            .frame(width: 80, height: 80)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isRecording ? LocalizedStringKey("Stop") : "Record"))
    }
}

private struct CircleIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Makes it obvious the picture is synthetic, not a broken camera.
private struct DemoBadge: View {
    var body: some View {
        Label("Demo frames", systemImage: "sparkles.tv")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel(Text("Demo frames. No camera on this device, showing a generated scene."))
    }
}
