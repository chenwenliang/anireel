import SwiftUI

/// Douyin-style capture page (D9): full-bleed preview, close and style chip on top, a right-hand
/// tool rail, style tabs above the shutter, style panel and latest clip either side of it.
struct CameraScreen: View {
    let onClose: () -> Void
    /// The result screen's Done: back to the feed.
    let onFinish: () -> Void
    let onOpenMyClips: () -> Void
    @State private var model: CameraModel
    @State private var showsGrid = false
    @State private var isPeeking = false
    @State private var isShowingStylePanel = false
    @State private var isShowingSettings = false
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(
        packs: [any StylePack],
        style: StyleID,
        account: AccountStore,
        library: ClipLibrary,
        defaults: CaptureDefaults,
        onClose: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onOpenMyClips: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.onFinish = onFinish
        self.onOpenMyClips = onOpenMyClips
        _model = State(initialValue: CameraModel(packs: packs, style: style, account: account, library: library, defaults: defaults))
    }

    var body: some View {
        ZStack {
            Theme.Palette.stage.ignoresSafeArea()
            switch model.phase {
            case .starting:
                ProgressView().tint(.white)
                    .accessibilityLabel(Text("Starting camera"))
            case .permissionDenied:
                PermissionDeniedView(kind: .camera)
            case .running(let preview, let context):
                MetalPreview(renderer: preview, device: context.device)
                    .ignoresSafeArea()
                    .overlay {
                        if showsGrid { GridOverlay().ignoresSafeArea().allowsHitTesting(false) }
                    }
                    .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
                        isPeeking = pressing
                        preview.setShowsOriginal(pressing)
                    })
                    .accessibilityElement()
                    .accessibilityLabel(Text("Live preview in \(model.pack.descriptor.title) style"))
                    .accessibilityHint(Text("Touch and hold to see the original camera picture."))
                    .accessibilityAddTraits(.isImage)
                CaptureChrome(
                    model: model,
                    showsGrid: $showsGrid,
                    isPeeking: isPeeking,
                    onShowStylePanel: { isShowingStylePanel = true },
                    onShowSettings: { isShowingSettings = true },
                    onOpenMyClips: onOpenMyClips
                )
            case .failed:
                StateMessageView(
                    systemImage: "camera.badge.ellipsis",
                    title: "Camera unavailable",
                    message: "Another app may be using the camera. Close it and try again.",
                    onDark: true
                ) {
                    Button("Try Again") { Task { await model.start() } }
                        .buttonStyle(.gradient)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            // Leaving mid-clip would end it; the close button returns once the clip is saved.
            if !model.recording.isBusy, model.countdown == nil {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
                .accessibilityLabel(Text("Close"))
                .padding(.leading, 8)
            }
        }
        .statusBarHidden()
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { model.interrupt() }
        }
        .onChange(of: model.styleID, initial: true) { _, style in
            preferences.preferences.lastStyle = style
        }
        .sheet(isPresented: $isShowingStylePanel) {
            StylePanel(packs: model.packs, selected: model.styleID, canChange: model.canChangeStyle) {
                model.selectStyle($0)
                isShowingStylePanel = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingSettings) {
            CameraSettingsSheet(model: model)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(get: { model.isAccountRequired }, set: { model.isAccountRequired = $0 })) {
            RegistrationWall { model.accountProvided() }
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: isShowing(.saved)) {
            ResultView(
                clip: model.savedClip,
                library: model.library,
                nextStyles: StyleChoice.alternatives(to: model.styleID, available: model.packs.map(\.descriptor.id))
                    .compactMap { id in model.packs.first { $0.descriptor.id == id }?.descriptor },
                onNextStyle: { style in
                    // Back to a ready camera first: styles only change while idle.
                    model.dismissResult()
                    model.selectStyle(style)
                }
            ) {
                model.dismissResult()
            } onDone: {
                model.dismissResult()
                onFinish()
            }
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

private struct CaptureChrome: View {
    let model: CameraModel
    @Binding var showsGrid: Bool
    let isPeeking: Bool
    let onShowStylePanel: () -> Void
    let onShowSettings: () -> Void
    let onOpenMyClips: () -> Void

    private var elapsed: TimeInterval {
        if case .recording(let elapsed) = model.recording { elapsed } else { 0 }
    }

    private var isRecording: Bool {
        if case .recording = model.recording { true } else { false }
    }

    /// Tools and style controls step aside while a clip is in flight or counting down.
    private var isCapturing: Bool { model.recording.isBusy || model.countdown != nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(alignment: .top) {
                if model.isDemo { DemoBadge() }
                Spacer()
                if !isCapturing { ToolRail(model: model, showsGrid: $showsGrid, onShowSettings: onShowSettings) }
            }
            .padding(.top, 12)
            Spacer()
            if let countdown = model.countdown {
                Text(verbatim: "\(countdown)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel(Text("Recording starts in \(countdown)"))
                Spacer()
            }
            Group {
                if isRecording {
                    TimerBadge(elapsed: elapsed)
                } else {
                    StyleTabs(packs: model.packs, selected: model.styleID) { model.selectStyle($0) }
                        .disabled(!model.canChangeStyle)
                        .opacity(isCapturing ? 0 : 1)
                }
            }
            .frame(height: 40)
            .padding(.bottom, 16)
            bottomRow
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 12)
        .animation(.default, value: model.recording)
        .animation(.default, value: model.countdown)
    }

    private var topBar: some View {
        ZStack {
            if isPeeking {
                Pill(text: Text("Original"), systemImage: "eye")
            } else if !isCapturing {
                Button(action: onShowStylePanel) {
                    Pill(text: Text(model.pack.descriptor.title), systemImage: "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Style: \(model.pack.descriptor.title)"))
                .accessibilityHint(Text("Opens the style panel."))
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
    }

    private var bottomRow: some View {
        HStack(alignment: .center) {
            Button(action: onShowStylePanel) {
                VStack(spacing: 4) {
                    StyleCover(style: model.styleID, cornerRadius: Theme.Radius.small)
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(.white, lineWidth: 2))
                    Text("Styles").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!model.canChangeStyle)
            .opacity(isCapturing ? 0 : 1)
            .frame(maxWidth: .infinity)

            RecordButton(isRecording: isRecording, progress: elapsed / DurationGuard.limit) {
                model.recordButtonTapped()
            }
            .disabled(!(isRecording || model.recording == .ready))

            Button(action: onOpenMyClips) {
                VStack(spacing: 4) {
                    Group {
                        if let latest = model.library.clips.first {
                            ClipThumbnail(url: model.library.url(for: latest))
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(.white, lineWidth: 2))
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                    }
                    Text("My Clips").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isCapturing)
            .opacity(isCapturing ? 0 : 1)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Right-hand vertical rail: icon over label, Douyin-style.
private struct ToolRail: View {
    let model: CameraModel
    @Binding var showsGrid: Bool
    let onShowSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            RailButton(systemImage: "arrow.triangle.2.circlepath.camera", title: "Flip", spokenLabel: Text("Switch camera")) {
                Task { await model.toggleCamera() }
            }
            if model.isTorchAvailable {
                RailButton(systemImage: model.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill", title: "Torch", isOn: model.isTorchOn) {
                    Task { await model.toggleTorch() }
                }
                .accessibilityValue(Text(model.isTorchOn ? LocalizedStringKey("On") : "Off"))
            }
            if !model.isDemo {
                let silent = model.isMuted || !model.microphoneAvailable
                RailButton(
                    systemImage: silent ? "mic.slash.fill" : "mic.fill",
                    title: "Microphone",
                    isOn: !silent,
                    spokenLabel: model.microphoneAvailable ? Text(model.isMuted ? LocalizedStringKey("Unmute") : "Mute") : Text("Microphone access is off")
                ) {
                    model.isMuted.toggle()
                }
                .disabled(!model.microphoneAvailable)
            }
            RailButton(systemImage: model.isSelfTimerOn ? "timer.circle.fill" : "timer", title: "Timer", isOn: model.isSelfTimerOn, spokenLabel: Text("3-second timer")) {
                model.isSelfTimerOn.toggle()
            }
            .accessibilityValue(Text(model.isSelfTimerOn ? LocalizedStringKey("On") : "Off"))
            RailButton(systemImage: "grid", title: "Grid", isOn: showsGrid) { showsGrid.toggle() }
                .accessibilityValue(Text(showsGrid ? LocalizedStringKey("On") : "Off"))
            RailButton(systemImage: "slider.horizontal.3", title: "Settings", action: onShowSettings)
        }
    }
}

private struct RailButton: View {
    let systemImage: String
    let title: LocalizedStringKey
    var isOn = false
    /// VoiceOver label when it should say more than the short visible title.
    var spokenLabel: Text?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                // Active tools invert to a white disc with a coral glyph, which reads on any scene (D10).
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accent : .white)
                    .frame(width: 36, height: 36)
                    .background(isOn ? Color.white : Color.black.opacity(0.22), in: Circle())
                    .animation(.easeOut(duration: 0.15), value: isOn)
                Text(title).font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3)
            }
            .frame(minWidth: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel ?? Text(title))
        .accessibilityAddTraits(.isButton)
    }
}

/// Text tabs above the shutter; the selected style is a white pill.
private struct StyleTabs: View {
    let packs: [any StylePack]
    let selected: StyleID
    let onSelect: (StyleID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(packs, id: \.descriptor.id) { pack in
                let isSelected = pack.descriptor.id == selected
                Button { onSelect(pack.descriptor.id) } label: {
                    Text(pack.descriptor.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? Theme.Palette.ink : .white.opacity(0.8))
                        .background { if isSelected { Capsule().fill(.white) } }
                        .shadow(color: isSelected ? .clear : .black.opacity(0.4), radius: 3)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .animation(.snappy, value: selected)
    }
}

/// The full style panel: covers for every style plus the coming-soon cell.
private struct StylePanel: View {
    let packs: [any StylePack]
    let selected: StyleID
    let canChange: Bool
    let onSelect: (StyleID) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Styles").font(Theme.Typography.title)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(packs, id: \.descriptor.id) { pack in
                    let isSelected = pack.descriptor.id == selected
                    Button { onSelect(pack.descriptor.id) } label: {
                        VStack(spacing: 6) {
                            StyleCover(style: pack.descriptor.id, cornerRadius: Theme.Radius.medium)
                                .aspectRatio(3 / 4, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                        .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 3)
                                )
                            Text(pack.descriptor.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .disabled(!canChange)
            ComingSoonCard(compact: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.gutter)
    }
}

private struct CameraSettingsSheet: View {
    let model: CameraModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mirror front camera", isOn: Binding(
                        get: { model.configuration.mirrorsFront },
                        set: { _ in Task { await model.toggleMirroring() } }
                    ))
                    .disabled(model.configuration.position != .front || model.recording.isBusy)
                } footer: {
                    Text("Applies to the front camera.")
                }
                Section {
                    Label("Touch and hold the preview to see the original picture.", systemImage: "hand.tap")
                    Label("Clips can be up to 30 seconds long.", systemImage: "timer")
                } header: {
                    Text("Tips")
                } footer: {
                    Text("Default camera and mute live in Me › Settings.")
                }
            }
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Shown when the gate blocks a guest: a sheet over the camera, never a dead end.
private struct RegistrationWall: View {
    let onSignedIn: () -> Void
    @State private var authScreen: AuthScreen?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.Palette.secondaryInk.opacity(0.6))
                }
                .accessibilityLabel(Text("Close"))
            }
            BrandMark(size: 52, gradient: true)
            Text("Keep recording with a free account")
                .font(Theme.Typography.title)
                .multilineTextAlignment(.center)
            Text("Unlimited recordings · Stored only on this iPhone · No email, no tracking")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryInk)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button("Create Account") { authScreen = .register }
                .buttonStyle(.gradient)
            Button("Log In") { authScreen = .login }
                .buttonStyle(.secondary)
        }
        .padding(Theme.Spacing.gutter)
        .sheet(item: $authScreen) { screen in
            AuthFlowView(start: screen) {
                authScreen = nil
                onSignedIn()
            }
        }
    }
}

/// Rule-of-thirds lines drawn over the preview only; never part of the recorded frames.
private struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let size = geometry.size
                for i in 1...2 {
                    let x = size.width * CGFloat(i) / 3
                    let y = size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct TimerBadge: View {
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 8, height: 8)
            Text(format(elapsed)).monospacedDigit()
            Text(verbatim: "/ " + format(DurationGuard.limit)).monospacedDigit().opacity(0.6)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.35), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Recording, \(format(elapsed)) recorded, \(format(DurationGuard.limit - elapsed)) left"))
    }

    private func format(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// White ring with a coral core; while recording the core becomes a stop square and the ring
/// fills over the 30-second limit.
private struct RecordButton: View {
    let isRecording: Bool
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(.white.opacity(isRecording ? 0.35 : 1), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: isRecording ? 8 : 34, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: isRecording ? 30 : 66, height: isRecording ? 30 : 66)
            }
            .frame(width: 84, height: 84)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isRecording ? LocalizedStringKey("Stop") : "Record"))
    }
}

/// Makes it obvious the picture is synthetic, not a broken camera.
private struct DemoBadge: View {
    var body: some View {
        Pill(text: Text("Demo frames"), systemImage: "sparkles.tv")
            .accessibilityLabel(Text("Demo frames. No camera on this device, showing a generated scene."))
    }
}
