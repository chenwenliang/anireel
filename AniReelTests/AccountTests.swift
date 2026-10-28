import Foundation
import XCTest
@testable import AniReel

final class InMemoryStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SecureStoreKey: Data] = [:]

    func data(for key: SecureStoreKey) throws -> Data? {
        lock.withLock { items[key] }
    }

    func set(_ data: Data?, for key: SecureStoreKey) throws {
        lock.withLock { items[key] = data }
    }

    var allData: [Data] { lock.withLock { Array(items.values) } }
}

final class RecordingGateTests: XCTestCase {
    private let account = AccountState.signedIn(Account(email: "a@b.co"))

    func testGuestFirstRecordingIsAllowed() {
        XCTAssertEqual(RecordingGate.decide(account: .guest, savedGuestRecordings: 0), .allowed)
    }

    func testGuestSecondRecordingRequiresAccount() {
        XCTAssertEqual(RecordingGate.decide(account: .guest, savedGuestRecordings: 1), .requiresAccount)
        XCTAssertEqual(RecordingGate.decide(account: .guest, savedGuestRecordings: 7), .requiresAccount)
    }

    func testSignedInAccountsAreUnlimited() {
        XCTAssertEqual(RecordingGate.decide(account: account, savedGuestRecordings: 0), .allowed)
        XCTAssertEqual(RecordingGate.decide(account: account, savedGuestRecordings: 50), .allowed)
    }

    func testSavedGuestCountPersistsAcrossLaunches() {
        let store = InMemoryStore()
        XCTAssertEqual(GuestUsageCounter(store: store).savedRecordings, 0)
        GuestUsageCounter(store: store).recordSavedClip()
        let relaunched = GuestUsageCounter(store: store)
        XCTAssertEqual(relaunched.savedRecordings, 1)
        XCTAssertEqual(RecordingGate.decide(account: .guest, savedGuestRecordings: relaunched.savedRecordings), .requiresAccount)
    }

    func testOnlyASuccessfulSaveCountsTowardTheAllowance() {
        let clip = URL(fileURLWithPath: "/tmp/clip.mp4")
        func effects(_ events: [RecordingEvent]) -> [RecordingEffect] {
            events.reduce((RecordingPhase.ready, [RecordingEffect]())) { state, event in
                let (next, effects) = RecordingMachine.reduce(state.0, event)
                return (next, state.1 + effects)
            }.1
        }
        let tooShort = effects([.startRequested, .stopRequested, .finished(clip, duration: 0.5), .acknowledged])
        let saveFailedThenDiscarded = effects([.startRequested, .stopRequested, .finished(clip, duration: 5), .saveFailed, .discardRequested])
        let writerFailed = effects([.startRequested, .writingFailed, .acknowledged])
        let saved = effects([.startRequested, .stopRequested, .finished(clip, duration: 5), .saveFailed, .retryRequested, .saveSucceeded])

        XCTAssertFalse(tooShort.contains(.clipSaved(clip)))
        XCTAssertFalse(saveFailedThenDiscarded.contains(.clipSaved(clip)))
        XCTAssertFalse(writerFailed.contains(.clipSaved(clip)))
        XCTAssertEqual(saved.filter { $0 == .clipSaved(clip) }.count, 1)
    }

    @MainActor
    func testAccountStoreCountsGuestSavesOnlyAndUnlocksAfterRegistering() async throws {
        let store = InMemoryStore()
        let accounts = AccountStore(service: LocalAuthService(store: store), usage: GuestUsageCounter(store: store))
        XCTAssertEqual(accounts.recordingDecision, .allowed)

        accounts.noteClipSaved()
        XCTAssertEqual(accounts.recordingDecision, .requiresAccount)

        try await accounts.register(email: "new@anireel.app", password: "secret123")
        XCTAssertEqual(accounts.recordingDecision, .allowed)
        accounts.noteClipSaved()
        XCTAssertEqual(GuestUsageCounter(store: store).savedRecordings, 1)

        await accounts.signOut()
        XCTAssertEqual(accounts.recordingDecision, .requiresAccount)
    }
}

final class CredentialRulesTests: XCTestCase {
    func testEmailValidation() {
        XCTAssertTrue(CredentialRules.isValidEmail("Someone@Example.com "))
        for bad in ["", "plain", "@example.com", "a@b", "a@b.", "a b@c.de", "a@@c.de", "a@.de"] {
            XCTAssertFalse(CredentialRules.isValidEmail(bad), bad)
        }
    }

    func testPasswordRules() {
        XCTAssertEqual(CredentialRules.passwordIssues("abc12345"), [])
        XCTAssertEqual(CredentialRules.passwordIssues("ab1"), [.passwordTooShort])
        XCTAssertEqual(CredentialRules.passwordIssues("abcdefgh"), [.passwordNeedsLetterAndDigit])
    }

    func testRegistrationReportsEveryIssue() {
        XCTAssertEqual(
            CredentialRules.registrationIssues(email: "nope", password: "short", confirmation: "other"),
            [.emailInvalid, .passwordTooShort, .passwordNeedsLetterAndDigit, .confirmationMismatch]
        )
        XCTAssertEqual(CredentialRules.registrationIssues(email: "a@b.co", password: "abc12345", confirmation: "abc12345"), [])
    }
}

final class LocalAuthServiceTests: XCTestCase {
    func testRegisterStartsAPersistentSession() async throws {
        let store = InMemoryStore()
        let account = try await LocalAuthService(store: store).register(email: " New@AniReel.app", password: "secret123")
        XCTAssertEqual(account.email, "new@anireel.app")
        let relaunched = LocalAuthService(store: store)
        let restored = await relaunched.currentAccount()
        XCTAssertEqual(restored, account)
    }

    func testDuplicateEmailIsRejectedCaseInsensitively() async throws {
        let service = LocalAuthService(store: InMemoryStore())
        _ = try await service.register(email: "a@b.co", password: "secret123")
        do {
            _ = try await service.register(email: "A@B.CO", password: "other1234")
            XCTFail("expected emailInUse")
        } catch {
            XCTAssertEqual(error as? AuthError, .emailInUse)
        }
    }

    func testSignInChecksThePassword() async throws {
        let service = LocalAuthService(store: InMemoryStore())
        _ = try await service.register(email: "a@b.co", password: "secret123")
        await service.signOut()
        do {
            _ = try await service.signIn(email: "a@b.co", password: "wrong1234")
            XCTFail("expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
        let account = try await service.signIn(email: "A@b.co", password: "secret123")
        XCTAssertEqual(account.email, "a@b.co")
    }

    func testPasswordsAreNeverStoredAndSaltsDiffer() async throws {
        let store = InMemoryStore()
        let service = LocalAuthService(store: store)
        _ = try await service.register(email: "one@b.co", password: "secret123")
        _ = try await service.register(email: "two@b.co", password: "secret123")
        XCTAssertFalse(store.allData.contains { $0.range(of: Data("secret123".utf8)) != nil })

        let records = try ["one@b.co", "two@b.co"].map { email in
            try JSONDecoder().decode(LocalAuthService.PasswordRecord.self, from: XCTUnwrap(store.data(for: .accountRecord(email))))
        }
        XCTAssertEqual(records[0].salt.count, 16)
        XCTAssertNotEqual(records[0].salt, records[1].salt)
        XCTAssertNotEqual(records[0].hash, records[1].hash)
    }

    func testSignOutEndsTheSession() async throws {
        let service = LocalAuthService(store: InMemoryStore())
        _ = try await service.register(email: "a@b.co", password: "secret123")
        await service.signOut()
        let current = await service.currentAccount()
        XCTAssertNil(current)
    }

    func testOnDevicePasswordReset() async throws {
        let service = LocalAuthService(store: InMemoryStore())
        _ = try await service.register(email: "a@b.co", password: "secret123")
        let route = try await service.requestPasswordReset(email: "a@b.co")
        XCTAssertEqual(route, .onDevice(email: "a@b.co"))
        try await service.resetPasswordOnDevice(email: "a@b.co", newPassword: "fresh4567")
        let account = try await service.signIn(email: "a@b.co", password: "fresh4567")
        XCTAssertEqual(account.email, "a@b.co")
    }

    func testDeleteAccountRemovesItsRecord() async throws {
        let store = InMemoryStore()
        let service = LocalAuthService(store: store)
        _ = try await service.register(email: "a@b.co", password: "secret123")
        do {
            try await service.deleteAccount(password: "wrong1234")
            XCTFail("expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
        XCTAssertNotNil(try store.data(for: .accountRecord("a@b.co")))

        try await service.deleteAccount(password: "secret123")
        XCTAssertNil(try store.data(for: .accountRecord("a@b.co")))
        XCTAssertNil(try store.data(for: .session))
        let current = await service.currentAccount()
        XCTAssertNil(current)
    }
}
