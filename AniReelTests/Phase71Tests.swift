import Foundation
import XCTest
@testable import AniReel

final class NextStyleTests: XCTestCase {
    func testAlternativesAreEveryOtherStyleInRegistryOrder() {
        let all = StyleRegistry.shipping.packs.map(\.descriptor.id)
        XCTAssertEqual(StyleChoice.alternatives(to: ChibiStylePack.id, available: all), [GhibliStylePack.id, NPRStylePack.id])
        XCTAssertEqual(StyleChoice.alternatives(to: StyleID(rawValue: "gone"), available: all), all)
        XCTAssertTrue(StyleChoice.alternatives(to: NPRStylePack.id, available: [NPRStylePack.id]).isEmpty)
    }
}

final class ReelIndicatorTests: XCTestCase {
    func testSinglePageShowsNoStrip() {
        XCTAssertNil(ReelIndicator.make(count: 0, current: 0))
        XCTAssertNil(ReelIndicator.make(count: 1, current: 0))
    }

    func testShortFeedsShowEveryPage() {
        XCTAssertEqual(ReelIndicator.make(count: 3, current: 1), ReelIndicator(pages: 0..<3, current: 1))
    }

    func testLongFeedsWindowAroundTheCurrentPage() {
        XCTAssertEqual(ReelIndicator.make(count: 20, current: 0, maxSegments: 7)?.pages, 0..<7)
        XCTAssertEqual(ReelIndicator.make(count: 20, current: 10, maxSegments: 7)?.pages, 7..<14)
        XCTAssertEqual(ReelIndicator.make(count: 20, current: 19, maxSegments: 7)?.pages, 13..<20)
    }

    func testOutOfRangePositionsAreClamped() {
        XCTAssertEqual(ReelIndicator.make(count: 4, current: 9)?.current, 3)
        XCTAssertEqual(ReelIndicator.make(count: 4, current: -1)?.current, 0)
    }
}

final class ProfileStatsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func clip(daysAgo: Double, from now: Date) -> ClipRecord {
        ClipRecord(id: UUID(), fileName: "x.mp4", createdAt: now.addingTimeInterval(-daysAgo * 86_400), duration: 3, styleID: "npr", byteSize: 1)
    }

    func testCountsAllClipsAndOnlyThisWeeksClips() {
        // Thursday 2026-10-29 12:00 UTC; the week (Monday start) began 2026-10-26.
        let now = Date(timeIntervalSince1970: 1_793_275_200)
        let clips = [clip(daysAgo: 0, from: now), clip(daysAgo: 2, from: now), clip(daysAgo: 4, from: now), clip(daysAgo: 30, from: now)]
        let stats = ProfileStats.make(clips: clips, quota: .signedIn(email: "a@b.co"), now: now, calendar: calendar)
        XCTAssertEqual(stats, ProfileStats(clips: 4, thisWeek: 2, allowance: .unlimited))
    }

    func testAllowanceFollowsTheQuota() {
        let now = Date()
        XCTAssertEqual(ProfileStats.make(clips: [], quota: .guestFree(left: 1), now: now).allowance, .remaining(1))
        XCTAssertEqual(ProfileStats.make(clips: [], quota: .guestUsedUp, now: now).allowance, .remaining(0))
    }
}

final class PasswordResetStageTests: XCTestCase {
    func testMiddleStepNamesWhatTheBackendDoes() {
        XCTAssertEqual(PasswordResetStage.resetKind(for: nil), .onDevice)
        XCTAssertEqual(PasswordResetStage.resetKind(for: .onDevice(email: "a@b.co")), .onDevice)
        XCTAssertEqual(PasswordResetStage.resetKind(for: .emailSent(to: "a@b.co")), .inbox)
    }

    func testStepsUpToTheCurrentOneAreReached() {
        XCTAssertEqual(PasswordResetStage.allCases.filter { PasswordResetStage.email.isReached($0) }, [.email])
        XCTAssertEqual(PasswordResetStage.allCases.filter { PasswordResetStage.reset.isReached($0) }, [.email, .reset])
        XCTAssertEqual(PasswordResetStage.allCases.filter { PasswordResetStage.done.isReached($0) }, PasswordResetStage.allCases)
    }
}
