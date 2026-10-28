import CryptoKit
import Foundation
import Security

/// On-device accounts (docs/DECISIONS.md D6). Each account is one Keychain item holding a
/// random 16-byte salt and SHA-256(salt ‖ password); passwords are never stored. No network.
/// See docs/ACCOUNTS.md for why this is a V1 stand-in, not production auth.
actor LocalAuthService: AuthService {
    struct PasswordRecord: Codable, Equatable {
        /// Bump when the hashing scheme changes so old records can be migrated on sign-in.
        var version = 1
        let salt: Data
        let hash: Data
    }

    private let store: any SecureStore

    init(store: any SecureStore = KeychainStore()) {
        self.store = store
    }

    func currentAccount() async -> Account? {
        guard let data = try? store.data(for: .session),
              let email = String(data: data, encoding: .utf8),
              (try? record(for: email)) != nil
        else { return nil }
        return Account(email: email)
    }

    func register(email: String, password: String) async throws -> Account {
        let email = CredentialRules.normalizedEmail(email)
        guard CredentialRules.isValidEmail(email) else { throw AuthError.invalidEmail }
        guard CredentialRules.passwordIssues(password).isEmpty else { throw AuthError.weakPassword }
        guard try record(for: email) == nil else { throw AuthError.emailInUse }
        try save(Self.makeRecord(password: password), for: email)
        return try startSession(email)
    }

    func signIn(email: String, password: String) async throws -> Account {
        let email = CredentialRules.normalizedEmail(email)
        guard let record = try record(for: email), Self.matches(password, record) else {
            throw AuthError.invalidCredentials
        }
        return try startSession(email)
    }

    func signOut() async {
        try? store.set(nil, for: .session)
    }

    func deleteAccount(password: String) async throws {
        guard let account = await currentAccount() else { throw AuthError.accountNotFound }
        guard let record = try record(for: account.email), Self.matches(password, record) else {
            throw AuthError.invalidCredentials
        }
        do {
            try store.set(nil, for: .accountRecord(account.email))
            try store.set(nil, for: .session)
        } catch {
            throw AuthError.storageFailure
        }
    }

    func requestPasswordReset(email: String) async throws -> PasswordResetRoute {
        let email = CredentialRules.normalizedEmail(email)
        guard CredentialRules.isValidEmail(email) else { throw AuthError.invalidEmail }
        guard try record(for: email) != nil else { throw AuthError.accountNotFound }
        return .onDevice(email: email)
    }

    func resetPasswordOnDevice(email: String, newPassword: String) async throws {
        let email = CredentialRules.normalizedEmail(email)
        guard try record(for: email) != nil else { throw AuthError.accountNotFound }
        guard CredentialRules.passwordIssues(newPassword).isEmpty else { throw AuthError.weakPassword }
        try save(Self.makeRecord(password: newPassword), for: email)
    }

    private func startSession(_ email: String) throws -> Account {
        do {
            try store.set(Data(email.utf8), for: .session)
        } catch {
            throw AuthError.storageFailure
        }
        return Account(email: email)
    }

    private func record(for email: String) throws -> PasswordRecord? {
        do {
            guard let data = try store.data(for: .accountRecord(email)) else { return nil }
            return try JSONDecoder().decode(PasswordRecord.self, from: data)
        } catch {
            throw AuthError.storageFailure
        }
    }

    private func save(_ record: PasswordRecord, for email: String) throws {
        do {
            try store.set(try JSONEncoder().encode(record), for: .accountRecord(email))
        } catch {
            throw AuthError.storageFailure
        }
    }

    static func makeRecord(password: String) throws -> PasswordRecord {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw AuthError.storageFailure }
        return PasswordRecord(salt: salt, hash: hash(password, salt: salt))
    }

    static func hash(_ password: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(password.utf8)))
    }

    /// Constant-time comparison so timing does not reveal how much of the hash matched.
    static func matches(_ password: String, _ record: PasswordRecord) -> Bool {
        let candidate = hash(password, salt: record.salt)
        guard candidate.count == record.hash.count else { return false }
        return zip(candidate, record.hash).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
