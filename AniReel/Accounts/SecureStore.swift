import Foundation
import Security

struct SecureStoreKey: Hashable, Sendable {
    let service: String
    let account: String

    static func accountRecord(_ email: String) -> SecureStoreKey {
        SecureStoreKey(service: "com.anireel.accounts", account: email)
    }

    static let session = SecureStoreKey(service: "com.anireel.session", account: "current")
    static let savedGuestRecordings = SecureStoreKey(service: "com.anireel.usage", account: "savedGuestRecordings")
}

/// Small key → bytes store. Production uses the Keychain; tests use an in-memory store.
protocol SecureStore: Sendable {
    func data(for key: SecureStoreKey) throws -> Data?
    /// `nil` deletes the item.
    func set(_ data: Data?, for key: SecureStoreKey) throws
}

struct KeychainError: Error {
    let status: OSStatus
}

/// Generic-password items, readable after first unlock, never synced to iCloud or migrated to
/// another device. Keychain items outlive app deletion, so the guest allowance does too.
struct KeychainStore: SecureStore {
    func data(for key: SecureStoreKey) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    func set(_ data: Data?, for key: SecureStoreKey) throws {
        let query = baseQuery(key)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData] = data
            insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func baseQuery(_ key: SecureStoreKey) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: key.service,
            kSecAttrAccount: key.account,
            kSecAttrSynchronizable: false,
        ]
    }
}
