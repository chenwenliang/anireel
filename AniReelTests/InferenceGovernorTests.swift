import XCTest
@testable import AniReel

final class InferenceGovernorTests: XCTestCase {
    private let allSides = Set(InferenceGovernor.ladder)
    private let fast = InferenceGovernor.frameBudget / 2
    private let slow = InferenceGovernor.frameBudget * 2

    private func feed(_ governor: inout InferenceGovernor, frames: Int, time: TimeInterval, thermal: ProcessInfo.ThermalState = .nominal) {
        for _ in 0..<frames { _ = governor.record(frameTime: time, thermal: thermal) }
    }

    func testStartsAtDeviceTierSize() {
        XCTAssertEqual(InferenceGovernor(startingAt: DeviceTier.a13.inferenceSize, available: allSides)?.side, 384)
        XCTAssertEqual(InferenceGovernor(startingAt: DeviceTier.a14OrNewer.inferenceSize, available: allSides)?.side, 512)
    }

    func testStartsAtLargestBundledSizeNotAboveTier() {
        XCTAssertEqual(InferenceGovernor(startingAt: 512, available: [384, 256])?.side, 384)
        XCTAssertNil(InferenceGovernor(startingAt: 384, available: [512]))
        XCTAssertNil(InferenceGovernor(startingAt: 512, available: []))
    }

    func testSustainedSlowFramesStepDownOneSizePerWindow() {
        var governor = InferenceGovernor(startingAt: 512, available: allSides)!
        feed(&governor, frames: InferenceGovernor.window, time: slow)
        XCTAssertEqual(governor.side, 384)
        feed(&governor, frames: InferenceGovernor.window, time: slow)
        XCTAssertEqual(governor.side, 256)
    }

    func testOccasionalSlowFramesDoNotStepDown() {
        var governor = InferenceGovernor(startingAt: 512, available: allSides)!
        feed(&governor, frames: InferenceGovernor.window / 2, time: slow)
        feed(&governor, frames: InferenceGovernor.window / 2, time: fast)
        XCTAssertEqual(governor.side, 512)
    }

    func testSeriousThermalStateStepsDownEvenWhenFast() {
        var governor = InferenceGovernor(startingAt: 512, available: allSides)!
        feed(&governor, frames: InferenceGovernor.window, time: fast, thermal: .serious)
        XCTAssertEqual(governor.side, 384)
    }

    func testNeverStepsBelowSmallestSize() {
        var governor = InferenceGovernor(startingAt: 384, available: allSides)!
        feed(&governor, frames: InferenceGovernor.window * 5, time: slow, thermal: .critical)
        XCTAssertEqual(governor.side, 256)
    }

    func testNeverStepsBackUp() {
        var governor = InferenceGovernor(startingAt: 512, available: allSides)!
        feed(&governor, frames: InferenceGovernor.window, time: slow)
        feed(&governor, frames: InferenceGovernor.window * 10, time: fast)
        XCTAssertEqual(governor.side, 384)
    }

    func testFrameSizesArePortraitMultiplesOfEightWithSidePixelBudget() {
        XCTAssertEqual(InferenceGovernor.frameSize(for: 512).width, 384)
        XCTAssertEqual(InferenceGovernor.frameSize(for: 512).height, 680)
        XCTAssertEqual(InferenceGovernor.frameSize(for: 384).width, 288)
        XCTAssertEqual(InferenceGovernor.frameSize(for: 384).height, 512)
        XCTAssertEqual(InferenceGovernor.frameSize(for: 256).width, 192)
        XCTAssertEqual(InferenceGovernor.frameSize(for: 256).height, 344)
    }
}
