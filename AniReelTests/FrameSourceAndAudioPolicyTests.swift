import AVFoundation
import XCTest
@testable import AniReel

final class FrameSourceKindTests: XCTestCase {
    func testDevicesWithACameraUseTheRealCamera() {
        XCTAssertEqual(FrameSourceKind.select(isSimulator: false, hasCamera: true), .camera)
    }

    func testSimulatorAlwaysUsesDemoFrames() {
        XCTAssertEqual(FrameSourceKind.select(isSimulator: true, hasCamera: true), .demo)
        XCTAssertEqual(FrameSourceKind.select(isSimulator: true, hasCamera: false), .demo)
    }

    func testCameraLessHardwareUsesDemoFrames() {
        XCTAssertEqual(FrameSourceKind.select(isSimulator: false, hasCamera: false), .demo)
    }

    func testDemoSourceNeverAsksForCameraPermissionOrMicrophone() async {
        let source = FrameSourceKind.demo.makeSource()
        XCTAssertFalse(source.requiresCameraPermission)
        let hasAudio = await source.setAudioCapture(true)
        XCTAssertFalse(hasAudio)
    }
}

final class AudioSessionPolicyTests: XCTestCase {
    func testPreviewMixesWithOtherAudioAndCannotRecord() {
        let preview = AudioSessionPolicy.preview
        XCTAssertTrue(preview.category == .ambient || preview.options.contains(.mixWithOthers))
        XCTAssertNotEqual(preview.category, .playAndRecord)
        XCTAssertNotEqual(preview.category, .record)
    }

    func testRecordingCanCaptureTheMicrophone() {
        XCTAssertEqual(AudioSessionPolicy.recording.category, .playAndRecord)
        XCTAssertEqual(AudioSessionPolicy.recording.mode, .videoRecording)
    }
}
