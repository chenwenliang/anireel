import Foundation
import XCTest
@testable import AniReel

private let allStyles = [GhibliStylePack.id, ChibiStylePack.id, NPRStylePack.id]

private func clip(_ name: String, at seconds: TimeInterval) -> ClipRecord {
    ClipRecord(id: UUID(), fileName: name, createdAt: Date(timeIntervalSince1970: seconds), duration: 5, styleID: "npr", byteSize: 1)
}

final class HomeFeedTests: XCTestCase {
    func testEmptyLibraryShowsExactlyOneSamplePerStyleInRegistryOrder() {
        let samples = SampleWork.catalog(for: StyleRegistry.shipping.packs.map(\.descriptor.id))
        let items = HomeFeed.items(clips: [], samples: samples)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items, allStyles.map { style in .sample(samples.first { $0.style == style }!) })
    }

    func testAnyClipReplacesTheSamplesEntirely() {
        let samples = SampleWork.catalog(for: allStyles)
        let only = clip("a", at: 1)
        XCTAssertEqual(HomeFeed.items(clips: [only], samples: samples), [.clip(only)])
    }

    func testClipsAreNewestFirst() {
        let old = clip("old", at: 100)
        let new = clip("new", at: 300)
        let mid = clip("mid", at: 200)
        XCTAssertEqual(HomeFeed.items(clips: [old, new, mid], samples: SampleWork.catalog(for: allStyles)), [.clip(new), .clip(mid), .clip(old)])
    }

    func testFeedItemIdsAreUniqueAcrossKinds() {
        let samples = SampleWork.catalog(for: allStyles)
        let ids = HomeFeed.items(clips: [], samples: samples).map(\.id) + [HomeFeedItem.clip(clip("a", at: 1)).id]
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCatalogSkipsStylesWithoutACoverAndCoversAreDistinct() {
        let catalog = SampleWork.catalog(for: allStyles + [StyleID(rawValue: "future")])
        XCTAssertEqual(catalog.map(\.style), allStyles)
        XCTAssertEqual(Set(catalog.map(\.coverAssetName)).count, 3)
        XCTAssertNil(SampleWork.coverAssetName(for: StyleID(rawValue: "future")))
    }
}

final class StyleChoiceTests: XCTestCase {
    func testRequestedStyleWins() {
        XCTAssertEqual(StyleChoice.resolve(requested: ChibiStylePack.id, lastUsed: NPRStylePack.id, available: allStyles), ChibiStylePack.id)
    }

    func testFallsBackToLastUsedThenFirst() {
        XCTAssertEqual(StyleChoice.resolve(requested: nil, lastUsed: NPRStylePack.id, available: allStyles), NPRStylePack.id)
        XCTAssertEqual(StyleChoice.resolve(requested: nil, lastUsed: nil, available: allStyles), GhibliStylePack.id)
    }

    func testUnknownStylesAreIgnored() {
        let gone = StyleID(rawValue: "removed")
        XCTAssertEqual(StyleChoice.resolve(requested: gone, lastUsed: gone, available: allStyles), GhibliStylePack.id)
        XCTAssertNil(StyleChoice.resolve(requested: nil, lastUsed: nil, available: []))
    }
}

final class LastUsedStyleTests: XCTestCase {
    func testDefaultsToNone() {
        XCTAssertNil(AppPreferences().lastStyle)
    }

    @MainActor
    func testPersistsAcrossLaunches() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("preferences.json")
        let file = JSONFileStore<AppPreferences>(url: url)
        PreferencesStore(file: file).preferences.lastStyle = ChibiStylePack.id
        XCTAssertEqual(PreferencesStore(file: file).preferences.lastStyle, ChibiStylePack.id)
    }

    func testPhase6FilesWithoutTheKeyStillLoad() throws {
        let json = Data(#"{"capture":{"position":"front"},"hasCompletedOnboarding":true}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: json)
        XCTAssertNil(decoded.lastStyle)
        XCTAssertTrue(decoded.hasCompletedOnboarding)
    }
}

final class ShellStateTests: XCTestCase {
    func testStartsOnTheWorksFeedWithNoCamera() {
        let shell = ShellState()
        XCTAssertEqual(shell.tab, .works)
        XCTAssertNil(shell.camera)
        XCTAssertTrue(shell.profilePath.isEmpty)
    }

    func testCentreButtonOpensTheLastUsedStyle() {
        var shell = ShellState()
        shell.openCamera(style: nil, lastUsed: NPRStylePack.id, available: allStyles)
        XCTAssertEqual(shell.camera, CameraRoute(style: NPRStylePack.id))
    }

    func testSampleCtaOpensTheSampleStyle() {
        var shell = ShellState()
        shell.openCamera(style: ChibiStylePack.id, lastUsed: NPRStylePack.id, available: allStyles)
        XCTAssertEqual(shell.camera?.style, ChibiStylePack.id)
    }

    func testCloseKeepsTheTabAndDoneReturnsToTheFeed() {
        var shell = ShellState()
        shell.select(.styles)
        shell.openCamera(style: nil, lastUsed: nil, available: allStyles)
        shell.closeCamera()
        XCTAssertEqual(shell.tab, .styles)
        XCTAssertNil(shell.camera)

        shell.openCamera(style: nil, lastUsed: nil, available: allStyles)
        shell.finishCapture()
        XCTAssertEqual(shell.tab, .works)
        XCTAssertNil(shell.camera)
    }

    func testOpenMyClipsLeavesTheCameraForTheGridInMe() {
        var shell = ShellState()
        shell.openCamera(style: nil, lastUsed: nil, available: allStyles)
        shell.openMyClips()
        XCTAssertNil(shell.camera)
        XCTAssertEqual(shell.tab, .me)
        XCTAssertEqual(shell.profilePath, [.myClips])
    }

    func testRetappingMePopsToItsRoot() {
        var shell = ShellState()
        shell.openMyClips()
        shell.select(.me)
        XCTAssertTrue(shell.profilePath.isEmpty)

        shell.profilePath = [.settings]
        shell.select(.works)
        XCTAssertEqual(shell.profilePath, [.settings], "switching tabs keeps each tab's place")
    }
}

final class QuotaStatusTests: XCTestCase {
    func testGuestStates() {
        XCTAssertEqual(QuotaStatus.make(account: .guest, freeGuestRecordingsLeft: 1), .guestFree(left: 1))
        XCTAssertEqual(QuotaStatus.make(account: .guest, freeGuestRecordingsLeft: 0), .guestUsedUp)
    }

    func testSignedInIgnoresTheGuestAllowance() {
        let account = Account(email: "a@b.co")
        XCTAssertEqual(QuotaStatus.make(account: .signedIn(account), freeGuestRecordingsLeft: 0), .signedIn(email: "a@b.co"))
    }
}

final class StyleChangePolicyTests: XCTestCase {
    func testStyleChangesOnlyWhileIdle() {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        XCTAssertTrue(RecordingPhase.ready.allowsStyleChange)
        let locked: [RecordingPhase] = [.recording(elapsed: 1), .finishing, .saving(url), .saved, .tooShort, .saveFailed(url), .recordingFailed]
        XCTAssertTrue(locked.allSatisfy { !$0.allowsStyleChange })
    }
}
