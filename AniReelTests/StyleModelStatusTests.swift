import XCTest
@testable import AniReel

final class StyleModelStatusTests: XCTestCase {
    private func stats(side: Int = 512) -> InferenceStats {
        InferenceStats(side: side, inferenceTimes: [0.05], prepareTimes: [0.002], elapsed: 1)!
    }

    func testOnlyRunningModelAllowsRecording() {
        XCTAssertTrue(StyleModelStatus.running(stats()).allowsRecording)
        XCTAssertFalse(StyleModelStatus.loading.allowsRecording)
        let reasons: [StyleModelStatus.UnavailableReason] = [.notBundled, .loadFailed, .inferenceFailed, .outOfResources]
        XCTAssertTrue(reasons.allSatisfy { !StyleModelStatus.unavailable($0).allowsRecording })
    }

    func testStatsCountOnlyRealInferencesOverWallTime() {
        let stats = InferenceStats(side: 384, inferenceTimes: [0.06, 0.07, 0.08, 0.09, 0.10, 0.11], prepareTimes: [0.001, 0.002, 0.003, 0.002, 0.002, 0.002], elapsed: 2)!
        XCTAssertEqual(stats.framesPerSecond, 3, accuracy: 1e-9)
        XCTAssertEqual(stats.inferenceP50, 0.08, accuracy: 1e-9)
        XCTAssertEqual(stats.inferenceP95, 0.11, accuracy: 1e-9)
        XCTAssertEqual(stats.prepareP50, 0.002, accuracy: 1e-9)
        XCTAssertEqual(stats.side, 384)
        XCTAssertEqual(stats.width, 288)
        XCTAssertEqual(stats.height, 512)
    }

    func testEmptyWindowHasNoStats() {
        XCTAssertNil(InferenceStats(side: 512, inferenceTimes: [], prepareTimes: [], elapsed: 1))
        XCTAssertNil(InferenceStats(side: 512, inferenceTimes: [0.05], prepareTimes: [0.001], elapsed: 0))
    }

    func testPercentileIsNearestRank() {
        let samples = (1...20).map { TimeInterval($0) }
        XCTAssertEqual(InferenceStats.percentile(0.5, of: samples), 10)
        XCTAssertEqual(InferenceStats.percentile(0.95, of: samples), 19)
        XCTAssertEqual(InferenceStats.percentile(0.95, of: [3]), 3)
        XCTAssertEqual(InferenceStats.percentile(0.5, of: []), 0)
    }

    func testSizeCyclingGoesDownThenWrapsToLargest() {
        let all = Set(InferenceGovernor.ladder)
        XCTAssertEqual(InferenceGovernor.nextSide(after: 512, available: all), 384)
        XCTAssertEqual(InferenceGovernor.nextSide(after: 384, available: all), 256)
        XCTAssertEqual(InferenceGovernor.nextSide(after: 256, available: all), 512)
        XCTAssertEqual(InferenceGovernor.nextSide(after: 384, available: [512, 384]), 512)
        XCTAssertNil(InferenceGovernor.nextSide(after: 512, available: []))
    }

    func testTenToFifteenFramesPerSecondKeepsTheLargerModel() {
        var governor = InferenceGovernor(startingAt: 512, available: Set(InferenceGovernor.ladder))!
        for _ in 0..<(InferenceGovernor.window * 3) {
            _ = governor.record(frameTime: 1.0 / 12, thermal: .nominal)
        }
        XCTAssertEqual(governor.side, 512)
    }

    func testEveryShippingStyleIsBackedByAModelSlot() {
        XCTAssertEqual(GhibliStylePack.modelName, "animegan_hayao")
        XCTAssertEqual(ChibiStylePack.modelName, "animegan_chibi")
        XCTAssertEqual(NPRStylePack.modelName, "animegan_shinkai")
    }
}
