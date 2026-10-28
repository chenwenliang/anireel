import Foundation
import XCTest
@testable import AniReel

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func record(_ name: String, at seconds: TimeInterval, bytes: Int64 = 100) -> ClipRecord {
    ClipRecord(id: UUID(), fileName: name, createdAt: Date(timeIntervalSince1970: seconds), duration: 5, styleID: "npr", byteSize: bytes)
}

final class ClipLibraryIndexTests: XCTestCase {
    func testClipsStayNewestFirstAndSizesAddUp() {
        var index = ClipLibraryIndex()
        index.insert(record("b", at: 200, bytes: 10))
        index.insert(record("a", at: 100, bytes: 20))
        index.insert(record("c", at: 300, bytes: 30))
        XCTAssertEqual(index.clips.map(\.fileName), ["c", "b", "a"])
        XCTAssertEqual(index.totalBytes, 60)
    }

    func testRemoveById() {
        var index = ClipLibraryIndex()
        let clip = record("a", at: 1)
        index.insert(clip)
        XCTAssertEqual(index.remove(id: clip.id), clip)
        XCTAssertNil(index.remove(id: clip.id))
        XCTAssertTrue(index.clips.isEmpty)
    }

    func testReconcileDropsRecordsWhoseFilesAreGone() {
        var index = ClipLibraryIndex()
        index.insert(record("kept.mp4", at: 1))
        index.insert(record("lost.mp4", at: 2))
        XCTAssertEqual(index.reconciled(existingFiles: ["kept.mp4", "library.json"]).clips.map(\.fileName), ["kept.mp4"])
    }

    func testIndexRoundTripsThroughJSON() throws {
        var index = ClipLibraryIndex()
        index.insert(record("a", at: 1))
        let decoded = try JSONDecoder().decode(ClipLibraryIndex.self, from: JSONEncoder().encode(index))
        XCTAssertEqual(decoded, index)
    }

    @MainActor
    func testLibraryImportsPersistsAndDeletesLocalCopies() throws {
        let directory = temporaryDirectory().appendingPathComponent("Clips")
        let source = temporaryDirectory().appendingPathComponent("temp.mp4")
        try Data(repeating: 7, count: 1234).write(to: source)

        let library = ClipLibrary(directory: directory)
        let clip = try library.importClip(from: source, duration: 4.5, styleID: NPRStylePack.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "temp file is left for the recorder to delete")
        XCTAssertEqual(clip.byteSize, 1234)
        XCTAssertEqual(clip.styleID, "npr")

        let relaunched = ClipLibrary(directory: directory)
        XCTAssertEqual(relaunched.clips, [clip])
        XCTAssertEqual(relaunched.index.totalBytes, 1234)

        relaunched.delete(clip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: relaunched.url(for: clip).path))
        XCTAssertTrue(ClipLibrary(directory: directory).clips.isEmpty)
    }

    @MainActor
    func testClearRemovesEveryLocalCopy() throws {
        let directory = temporaryDirectory().appendingPathComponent("Clips")
        let source = temporaryDirectory().appendingPathComponent("temp.mp4")
        try Data([1, 2, 3]).write(to: source)
        let library = ClipLibrary(directory: directory)
        let clips = try (0..<3).map { _ in try library.importClip(from: source, duration: 2, styleID: NPRStylePack.id) }
        library.deleteAll()
        XCTAssertTrue(library.clips.isEmpty)
        XCTAssertTrue(clips.allSatisfy { !FileManager.default.fileExists(atPath: library.url(for: $0).path) })
    }
}

final class CaptureStartTests: XCTestCase {
    func testGateIsCheckedBeforeAnyCountdown() {
        XCTAssertEqual(CaptureStart.plan(decision: .requiresAccount, selfTimer: true), .requireAccount)
        XCTAssertEqual(CaptureStart.plan(decision: .requiresAccount, selfTimer: false), .requireAccount)
    }

    func testSelfTimerCountsDownThreeSeconds() {
        XCTAssertEqual(CaptureStart.plan(decision: .allowed, selfTimer: true), .countdown(seconds: 3))
    }

    func testWithoutTimerRecordingStartsImmediately() {
        XCTAssertEqual(CaptureStart.plan(decision: .allowed, selfTimer: false), .startNow)
    }
}

final class PreferencesTests: XCTestCase {
    func testMissingFileGivesDefaults() {
        let store = JSONFileStore<AppPreferences>(url: temporaryDirectory().appendingPathComponent("none.json"))
        XCTAssertNil(store.load())
        let defaults = AppPreferences()
        XCTAssertEqual(defaults.capture.position, .back)
        XCTAssertTrue(defaults.capture.mirrorsFront)
        XCTAssertFalse(defaults.capture.mutedByDefault)
        XCTAssertFalse(defaults.hasCompletedOnboarding)
    }

    @MainActor
    func testPreferencesPersistAcrossLaunches() {
        let file = JSONFileStore<AppPreferences>(url: temporaryDirectory().appendingPathComponent("preferences.json"))
        let store = PreferencesStore(file: file)
        store.preferences.capture.position = .front
        store.preferences.capture.mutedByDefault = true
        store.preferences.hasCompletedOnboarding = true

        let relaunched = PreferencesStore(file: file)
        XCTAssertEqual(relaunched.preferences, store.preferences)
    }

    func testOlderFilesWithMissingKeysStillLoad() throws {
        let json = Data(#"{"capture":{"position":"front"}}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: json)
        XCTAssertEqual(decoded.capture.position, .front)
        XCTAssertTrue(decoded.capture.mirrorsFront)
        XCTAssertFalse(decoded.hasCompletedOnboarding)
    }
}

final class AccountDeletionTests: XCTestCase {
    @MainActor
    func testDeletingReturnsToGuestAndKeepsTheDeviceAllowanceUsed() async throws {
        let store = InMemoryStore()
        let accounts = AccountStore(service: LocalAuthService(store: store), usage: GuestUsageCounter(store: store))
        accounts.noteClipSaved()
        try await accounts.register(email: "a@b.co", password: "secret123")

        do {
            try await accounts.deleteAccount(password: "wrong1234")
            XCTFail("expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
        XCTAssertEqual(accounts.state, .signedIn(Account(email: "a@b.co")))

        try await accounts.deleteAccount(password: "secret123")
        XCTAssertEqual(accounts.state, .guest)
        XCTAssertNil(try store.data(for: .accountRecord("a@b.co")))
        XCTAssertNil(try store.data(for: .session))
        XCTAssertEqual(accounts.savedGuestRecordings, 1)
        XCTAssertEqual(accounts.recordingDecision, .requiresAccount)
    }

    @MainActor
    func testDeletingBeforeUsingTheFreeRecordingLeavesItAvailable() async throws {
        let store = InMemoryStore()
        let accounts = AccountStore(service: LocalAuthService(store: store), usage: GuestUsageCounter(store: store))
        try await accounts.register(email: "a@b.co", password: "secret123")
        try await accounts.deleteAccount(password: "secret123")
        XCTAssertEqual(accounts.recordingDecision, .allowed)
    }
}

final class LegalTextTests: XCTestCase {
    func testMarkupParsesIntoBlocks() {
        let text = """
        # Title
        Intro line one
        line two

        ## Section
        - first
        - second
        Closing.
        """
        XCTAssertEqual(LegalBlock.parse(text), [
            .title("Title"),
            .paragraph("Intro line one line two"),
            .heading("Section"),
            .bullet("first"),
            .bullet("second"),
            .paragraph("Closing."),
        ])
    }

    func testBothDocumentsShipInEnglishAndChinese() throws {
        for document in [LegalDocument.privacyPolicy, .terms] {
            for language in ["en", "zh-Hans"] {
                let url = try XCTUnwrap(
                    Bundle.main.url(forResource: document.resourceName, withExtension: "txt", subdirectory: nil, localization: language),
                    "\(document.resourceName) \(language)"
                )
                let blocks = LegalBlock.parse(try String(contentsOf: url, encoding: .utf8))
                XCTAssertTrue(blocks.contains { if case .title = $0 { true } else { false } })
                XCTAssertGreaterThan(blocks.count, 5)
            }
        }
    }
}
