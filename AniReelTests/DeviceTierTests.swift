import XCTest
@testable import AniReel

final class DeviceTierTests: XCTestCase {
    func testA13DevicesUse384() {
        for id in ["iPhone12,1", "iPhone12,3", "iPhone12,5", "iPhone12,8"] {
            XCTAssertEqual(DeviceTier(modelIdentifier: id), .a13, id)
        }
        XCTAssertEqual(DeviceTier.a13.inferenceSize, 384)
    }

    func testA14AndNewerUse512() {
        for id in ["iPhone13,2", "iPhone14,6", "iPhone15,2", "iPhone17,1", "iPhone99,1"] {
            XCTAssertEqual(DeviceTier(modelIdentifier: id), .a14OrNewer, id)
        }
        XCTAssertEqual(DeviceTier.a14OrNewer.inferenceSize, 512)
    }

    func testA12AndOlderAreBelowFloor() {
        for id in ["iPhone11,2", "iPhone11,8", "iPhone10,3"] {
            XCTAssertNil(DeviceTier(modelIdentifier: id), id)
        }
    }

    func testNonPhoneIdentifiersAreNotBlocked() {
        XCTAssertEqual(DeviceTier(modelIdentifier: "iPad13,4"), .a14OrNewer)
    }
}
