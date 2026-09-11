import Foundation
import Security

enum PasswordVerificationResult: Equatable {
    case match
    case mismatch
    case notFound
    case accessFailure(OSStatus)
    case decodeFailure
}

enum PasswordSaveResult: Equatable {
    case saved
    case encodingFailure
    case accessFailure(OSStatus)

    var succeeded: Bool {
        self == .saved
    }
}

protocol PasswordStoring {
    func savePassword(_ password: String) -> PasswordSaveResult
    func verifyPassword(_ password: String) -> PasswordVerificationResult
}

protocol KeychainAccessing {
    func copyMatching(
        _ query: CFDictionary,
        result: UnsafeMutablePointer<CFTypeRef?>?
    ) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

private struct SystemKeychainAccess: KeychainAccessing {
    func copyMatching(
        _ query: CFDictionary,
        result: UnsafeMutablePointer<CFTypeRef?>?
    ) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func add(_ attributes: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemAdd(attributes, result)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

/// Manages secure storage of the backup password in the macOS Keychain.
final class KeychainManager: PasswordStoring {
    static let shared = KeychainManager()

    private let service = "com.makmak.MakLock"
    private let account = "backup-password"
    private let passwordAttemptStateAccount = "password-attempt-state"

    private let keychain: KeychainAccessing

    init(keychain: KeychainAccessing = SystemKeychainAccess()) {
        self.keychain = keychain
    }

    /// Save a password to the Keychain.
    func savePassword(_ password: String) -> PasswordSaveResult {
        guard let data = password.data(using: .utf8) else { return .encodingFailure }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = keychain.update(
            query as CFDictionary,
            attributes: updateAttributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return .saved
        }
        guard updateStatus == errSecItemNotFound else {
            return .accessFailure(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = keychain.add(addQuery as CFDictionary, result: nil)
        if addStatus == errSecSuccess {
            return .saved
        }

        // Another writer may have created the item after our update query.
        if addStatus == errSecDuplicateItem {
            let retryStatus = keychain.update(
                query as CFDictionary,
                attributes: updateAttributes as CFDictionary
            )
            return retryStatus == errSecSuccess ? .saved : .accessFailure(retryStatus)
        }

        return .accessFailure(addStatus)
    }

    /// Verify a password against the stored Keychain entry.
    func verifyPassword(_ password: String) -> PasswordVerificationResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = keychain.copyMatching(query as CFDictionary, result: &result)

        if status == errSecItemNotFound {
            return .notFound
        }
        guard status == errSecSuccess else {
            return .accessFailure(status)
        }
        guard let data = result as? Data,
              let storedPassword = String(data: data, encoding: .utf8) else {
            return .decodeFailure
        }

        return storedPassword == password ? .match : .mismatch
    }

    /// Check whether a backup password exists in the Keychain.
    /// Uses attribute-only query to avoid triggering the Keychain authorization dialog.
    func hasPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = keychain.copyMatching(query as CFDictionary, result: &result)
        return status == errSecSuccess
    }

    /// Remove the stored password from the Keychain.
    @discardableResult
    func deletePassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = keychain.delete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    @discardableResult
    func savePasswordAttemptState(_ state: PasswordAttemptState) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAttemptStateAccount
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = keychain.update(
            query as CFDictionary,
            attributes: updateAttributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAttemptStateAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        return keychain.add(addQuery as CFDictionary, result: nil) == errSecSuccess
    }

    func loadPasswordAttemptState() -> PasswordAttemptState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAttemptStateAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard keychain.copyMatching(query as CFDictionary, result: &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(PasswordAttemptState.self, from: data)
    }

    @discardableResult
    func deletePasswordAttemptState() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAttemptStateAccount
        ]

        let status = keychain.delete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

}
