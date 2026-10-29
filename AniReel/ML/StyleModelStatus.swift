import Foundation

/// What the live style's model is doing. Only `.running` means the preview shows model output;
/// in every other state the preview is a dimmed placeholder and recording is blocked, so a
/// missing or broken model can never pass for the AI style.
enum StyleModelStatus: Equatable, Sendable {
    case loading
    case running(InferenceStats)
    case unavailable(UnavailableReason)

    enum UnavailableReason: Equatable, Sendable {
        /// The app ships no model for this style (docs/MODELS.md).
        case notBundled
        case loadFailed
        case inferenceFailed
        /// Buffers or GPU work could not be created for a frame.
        case outOfResources
    }

    var allowsRecording: Bool {
        if case .running = self { true } else { false }
    }
}

/// One reporting window of real model outputs. Every counted frame is a new inference;
/// the preview redrawing the same frame does not count.
struct InferenceStats: Equatable, Sendable {
    /// Ladder size (`InferenceGovernor.ladder`); `width` x `height` is the actual model input.
    let side: Int
    let width: Int
    let height: Int
    let framesPerSecond: Double
    let inferenceP50: TimeInterval
    let inferenceP95: TimeInterval
    /// Camera frame → model input resample on the GPU.
    let prepareP50: TimeInterval

    /// `nil` for an empty window.
    init?(side: Int, inferenceTimes: [TimeInterval], prepareTimes: [TimeInterval], elapsed: TimeInterval) {
        guard !inferenceTimes.isEmpty, elapsed > 0 else { return nil }
        self.side = side
        let size = InferenceGovernor.frameSize(for: side)
        width = size.width
        height = size.height
        framesPerSecond = Double(inferenceTimes.count) / elapsed
        inferenceP50 = Self.percentile(0.5, of: inferenceTimes)
        inferenceP95 = Self.percentile(0.95, of: inferenceTimes)
        prepareP50 = Self.percentile(0.5, of: prepareTimes)
    }

    /// Nearest-rank percentile; 0 for no samples.
    static func percentile(_ p: Double, of samples: [TimeInterval]) -> TimeInterval {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
