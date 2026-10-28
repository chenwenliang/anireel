import Foundation

struct Account: Equatable, Sendable {
    /// Normalized (trimmed, lowercased) email; the account's identity.
    let email: String
}

enum AccountState: Equatable, Sendable {
    case guest
    case signedIn(Account)
}

enum AuthError: Error, Equatable, Sendable {
    case invalidEmail
    case weakPassword
    case emailInUse
    case invalidCredentials
    case accountNotFound
    case unsupported
    case storageFailure
}

/// Where a password reset continues. Remote backends email a link; the on-device
/// implementation has no email channel and resets on this iPhone instead.
enum PasswordResetRoute: Equatable, Sendable {
    case emailSent(to: String)
    case onDevice(email: String)
}

/// Account backend boundary. Screens and `AccountStore` only see this protocol, so a remote
/// service (see docs/ACCOUNTS.md) replaces `LocalAuthService` without UI changes.
protocol AuthService: Sendable {
    /// The persisted session, if any, restored at launch.
    func currentAccount() async -> Account?
    func register(email: String, password: String) async throws -> Account
    func signIn(email: String, password: String) async throws -> Account
    func signOut() async
    /// Required by App Review for apps that create accounts (guideline 5.1.1(v)).
    /// The password is re-checked so a borrowed unlocked phone cannot delete the account.
    func deleteAccount(password: String) async throws
    func requestPasswordReset(email: String) async throws -> PasswordResetRoute
    /// Only for `PasswordResetRoute.onDevice`; remote services throw `.unsupported`.
    func resetPasswordOnDevice(email: String, newPassword: String) async throws
}
