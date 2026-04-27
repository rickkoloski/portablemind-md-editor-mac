// D18 phase 2 — bearer-token storage in the macOS Keychain.
//
// Single-account model for D18: one token under the service id below,
// account "default". D19 (connection-management UX) may move to a
// per-connection account so multiple PortableMind connections (or
// multiple tenants) can each have their own token.
//
// All operations are blocking; callers run them off the main actor if
// the keychain prompts the user (it shouldn't for our access group,
// but the API doesn't promise non-blocking behavior).

import Foundation
import Security

enum KeychainTokenError: Error {
    case unhandled(OSStatus)
    case decodeFailed
}

struct KeychainTokenStore {
    static let shared = KeychainTokenStore()

    private let service = "ai.portablemind.md-editor.harmoniq-token"
    private let account = "default"

    /// Save (or overwrite) the bearer token. Empty strings are
    /// rejected — use `clear()` to remove.
    func save(token: String) throws {
        guard !token.isEmpty else {
            throw KeychainTokenError.decodeFailed
        }
        let data = Data(token.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Try update first; if no item exists, fall back to add.
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                         updateAttrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainTokenError.unhandled(addStatus)
            }
        default:
            throw KeychainTokenError.unhandled(updateStatus)
        }
    }

    /// Load the bearer token. Returns nil if no token has been saved
    /// (or if the keychain entry was cleared). Throws only on
    /// unexpected errors.
    func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8)
            else { throw KeychainTokenError.decodeFailed }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainTokenError.unhandled(status)
        }
    }

    /// Remove the token. Idempotent — no-op if nothing was saved.
    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainTokenError.unhandled(status)
        }
    }
}
