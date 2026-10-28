import Foundation

/// Chooses the ML inference size. It starts at the device tier's size (D1) and may only step
/// down the ladder, when the device runs hot or a window of frames is mostly over budget.
struct InferenceGovernor {
    /// Sides of a square pixel budget. One fixed-shape model per side ships as `<model>_<side>`.
    static let ladder = [512, 384, 256]
    static let frameBudget: TimeInterval = 1.0 / 30
    static let window = 30

    private let sides: [Int]
    private var index = 0
    private var framesInWindow = 0
    private var slowFramesInWindow = 0

    var side: Int { sides[index] }

    /// `nil` when no model at or below the starting size is available.
    init?(startingAt start: Int, available: Set<Int>) {
        sides = Self.ladder.filter { $0 <= start && available.contains($0) }
        if sides.isEmpty { return nil }
    }

    /// Returns `true` when this frame caused a step down.
    mutating func record(frameTime: TimeInterval, thermal: ProcessInfo.ThermalState) -> Bool {
        framesInWindow += 1
        if frameTime > Self.frameBudget { slowFramesInWindow += 1 }
        guard framesInWindow >= Self.window else { return false }
        let isSlow = slowFramesInWindow * 2 > framesInWindow
        let isHot = thermal == .serious || thermal == .critical
        framesInWindow = 0
        slowFramesInWindow = 0
        guard isSlow || isHot, index + 1 < sides.count else { return false }
        index += 1
        return true
    }

    /// Portrait 3:4-ish frame with the same pixel count as `side`², rounded to multiples of 8
    /// as AnimeGAN requires. scripts/convert_animegan.py uses the same formula.
    static func frameSize(for side: Int) -> (width: Int, height: Int) {
        func roundTo8(_ value: Double) -> Int { Int((value / 8).rounded()) * 8 }
        return (roundTo8(Double(side) * 0.75), roundTo8(Double(side) * 4 / 3))
    }
}
