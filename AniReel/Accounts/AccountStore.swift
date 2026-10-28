import Observation

/// App-wide account state for the UI. Wraps an `AuthService` and the guest usage counter.
@MainActor
@Observable
final class AccountStore {
    private(set) var state: AccountState = .guest
    private(set) var savedGuestRecordings: Int

    @ObservationIgnored private let service: any AuthService
    @ObservationIgnored private let usage: GuestUsageCounter

    init(service: any AuthService, usage: GuestUsageCounter) {
        self.service = service
        self.usage = usage
        savedGuestRecordings = usage.savedRecordings
    }

    static func live() -> AccountStore {
        let store = KeychainStore()
        return AccountStore(service: LocalAuthService(store: store), usage: GuestUsageCounter(store: store))
    }

    var recordingDecision: RecordingGate.Decision {
        RecordingGate.decide(account: state, savedGuestRecordings: savedGuestRecordings)
    }

    var freeGuestRecordingsLeft: Int {
        max(0, RecordingGate.freeGuestRecordings - savedGuestRecordings)
    }

    func restoreSession() async {
        if let account = await service.currentAccount() { state = .signedIn(account) }
    }

    func register(email: String, password: String) async throws {
        state = .signedIn(try await service.register(email: email, password: password))
    }

    func signIn(email: String, password: String) async throws {
        state = .signedIn(try await service.signIn(email: email, password: password))
    }

    func signOut() async {
        await service.signOut()
        state = .guest
    }

    /// The device's saved-guest count is kept, so deleting an account never grants another
    /// free recording (docs/ACCOUNTS.md).
    func deleteAccount(password: String) async throws {
        try await service.deleteAccount(password: password)
        state = .guest
    }

    func requestPasswordReset(email: String) async throws -> PasswordResetRoute {
        try await service.requestPasswordReset(email: email)
    }

    func resetPasswordOnDevice(email: String, newPassword: String) async throws {
        try await service.resetPasswordOnDevice(email: email, newPassword: newPassword)
    }

    func noteClipSaved() {
        guard state == .guest else { return }
        savedGuestRecordings = usage.recordSavedClip()
    }
}
