import XCTest
@testable import AniReel

final class DurationGuardTests: XCTestCase {
    func testLimitIsInclusiveAtThirtySeconds() {
        XCTAssertFalse(DurationGuard.hasReachedLimit(29.99))
        XCTAssertTrue(DurationGuard.hasReachedLimit(30.0))
    }

    func testClipsUnderOneSecondAreDiscarded() {
        XCTAssertFalse(DurationGuard.keeps(0))
        XCTAssertFalse(DurationGuard.keeps(0.99))
        XCTAssertTrue(DurationGuard.keeps(1.0))
    }
}

final class RecordingMachineTests: XCTestCase {
    private let clip = URL(fileURLWithPath: "/tmp/clip.mp4")

    private func run(_ events: [RecordingEvent], from phase: RecordingPhase = .ready) -> (RecordingPhase, [RecordingEffect]) {
        events.reduce((phase, [RecordingEffect]())) { state, event in
            let (next, effects) = RecordingMachine.reduce(state.0, event)
            return (next, state.1 + effects)
        }
    }

    func testUserStopSavesClip() {
        let (phase, effects) = run([.startRequested, .progressed(5), .stopRequested, .finished(clip, duration: 5)])
        XCTAssertEqual(phase, .saving(clip))
        XCTAssertEqual(effects, [.beginWriting, .finishWriting, .save(clip)])
    }

    func testReachingThirtySecondsFinishesWithoutUserAction() {
        let (phase, effects) = run([.startRequested, .progressed(29.9), .progressed(30)])
        XCTAssertEqual(phase, .finishing)
        XCTAssertEqual(effects, [.beginWriting, .finishWriting])
    }

    func testProgressAfterStopIsIgnored() {
        let (phase, effects) = run([.startRequested, .stopRequested, .progressed(31), .stopRequested])
        XCTAssertEqual(phase, .finishing)
        XCTAssertEqual(effects, [.beginWriting, .finishWriting])
    }

    func testShortClipIsDeletedAndPromptsRetake() {
        let (phase, effects) = run([.startRequested, .stopRequested, .finished(clip, duration: 0.4)])
        XCTAssertEqual(phase, .tooShort)
        XCTAssertEqual(effects.last, .deleteFile(clip))
        XCTAssertEqual(RecordingMachine.reduce(phase, .acknowledged).0, .ready)
    }

    func testSaveFailureKeepsFileUntilRetrySucceeds() {
        let (failed, failEffects) = run([.saveFailed], from: .saving(clip))
        XCTAssertEqual(failed, .saveFailed(clip))
        XCTAssertFalse(failEffects.contains(.deleteFile(clip)))

        let (phase, effects) = run([.retryRequested, .saveSucceeded], from: failed)
        XCTAssertEqual(phase, .saved)
        XCTAssertEqual(effects, [.save(clip), .deleteFile(clip)])
    }

    func testDiscardAfterSaveFailureDeletesFile() {
        let (phase, effects) = run([.discardRequested], from: .saveFailed(clip))
        XCTAssertEqual(phase, .ready)
        XCTAssertEqual(effects, [.deleteFile(clip)])
    }

    func testWriterFailureEndsRecording() {
        XCTAssertEqual(run([.startRequested, .writingFailed]).0, .recordingFailed)
        XCTAssertEqual(run([.writingFailed], from: .finishing).0, .recordingFailed)
    }

    func testStartIsIgnoredWhileAClipIsInFlight() {
        for phase in [RecordingPhase.recording(elapsed: 3), .finishing, .saving(clip)] {
            XCTAssertTrue(phase.isBusy)
            XCTAssertEqual(RecordingMachine.reduce(phase, .startRequested).1, [])
        }
    }

    func testStopWhenIdleDoesNothing() {
        XCTAssertEqual(run([.stopRequested]).0, .ready)
    }
}
