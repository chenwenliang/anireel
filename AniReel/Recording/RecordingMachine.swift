import Foundation

enum DurationGuard {
    static let limit: TimeInterval = 30
    static let minimum: TimeInterval = 1

    static func hasReachedLimit(_ elapsed: TimeInterval) -> Bool { elapsed >= limit }
    static func keeps(_ duration: TimeInterval) -> Bool { duration >= minimum }
}

enum RecordingPhase: Equatable {
    case ready
    case recording(elapsed: TimeInterval)
    case finishing
    case saving(URL)
    case saved
    case tooShort
    case saveFailed(URL)
    case recordingFailed

    /// A clip is in flight; camera changes and leaving the screen are locked.
    var isBusy: Bool {
        switch self {
        case .recording, .finishing, .saving: true
        default: false
        }
    }
}

enum RecordingEvent: Equatable {
    case startRequested
    case progressed(TimeInterval)
    /// User stop, leaving the screen, or an interruption; all of them save what exists.
    case stopRequested
    case finished(URL, duration: TimeInterval)
    case writingFailed
    case saveSucceeded
    case saveFailed
    case retryRequested
    case discardRequested
    case acknowledged
}

enum RecordingEffect: Equatable {
    case beginWriting
    case finishWriting
    case save(URL)
    /// The only signal that a clip reached Photos; guest allowance counting and the local
    /// library key off it. Performed before the temp file is deleted.
    case clipSaved(URL)
    case deleteFile(URL)
}

/// Every recording rule lives here; events that do not apply to the current phase are ignored.
enum RecordingMachine {
    static func reduce(_ phase: RecordingPhase, _ event: RecordingEvent) -> (RecordingPhase, [RecordingEffect]) {
        switch (phase, event) {
        case (.ready, .startRequested):
            return (.recording(elapsed: 0), [.beginWriting])
        case (.recording, .progressed(let elapsed)):
            return DurationGuard.hasReachedLimit(elapsed)
                ? (.finishing, [.finishWriting])
                : (.recording(elapsed: elapsed), [])
        case (.recording, .stopRequested):
            return (.finishing, [.finishWriting])
        case (.recording, .writingFailed), (.finishing, .writingFailed):
            return (.recordingFailed, [])
        case (.finishing, .finished(let url, let duration)):
            return DurationGuard.keeps(duration)
                ? (.saving(url), [.save(url)])
                : (.tooShort, [.deleteFile(url)])
        case (.saving(let url), .saveSucceeded):
            return (.saved, [.clipSaved(url), .deleteFile(url)])
        case (.saving(let url), .saveFailed):
            return (.saveFailed(url), [])
        case (.saveFailed(let url), .retryRequested):
            return (.saving(url), [.save(url)])
        case (.saveFailed(let url), .discardRequested):
            return (.ready, [.deleteFile(url)])
        case (.saved, .acknowledged), (.tooShort, .acknowledged), (.recordingFailed, .acknowledged):
            return (.ready, [])
        default:
            return (phase, [])
        }
    }
}
