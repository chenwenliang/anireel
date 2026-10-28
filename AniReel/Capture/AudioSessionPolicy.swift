import AVFoundation

/// Preview never touches the user's music; the mic and a record-capable session exist only
/// while a clip with sound is being recorded (docs/DECISIONS.md D5).
enum AudioSessionPolicy: Equatable {
    case preview
    case recording

    var category: AVAudioSession.Category {
        switch self {
        case .preview: .ambient
        case .recording: .playAndRecord
        }
    }

    var mode: AVAudioSession.Mode {
        switch self {
        case .preview: .default
        case .recording: .videoRecording
        }
    }

    var options: AVAudioSession.CategoryOptions {
        switch self {
        case .preview: [.mixWithOthers]
        case .recording: [.defaultToSpeaker, .allowBluetoothA2DP]
        }
    }

    /// Recording activates the session (other audio pauses); preview deactivates it and lets
    /// other apps resume.
    func apply() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(category, mode: mode, options: options)
        switch self {
        case .preview: try session.setActive(false, options: .notifyOthersOnDeactivation)
        case .recording: try session.setActive(true)
        }
    }
}
