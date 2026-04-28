// Bearer-token storage.
//
// TEMPORARY (backlog i04): file-based, not Keychain.
//
// Why: ad-hoc-signed builds (project.yml: CODE_SIGN_IDENTITY "-",
// empty DEVELOPMENT_TEAM) cause macOS to attach a cdhash-bound ACL to
// every Keychain item we write. Each rebuild changes the cdhash, so
// the next launch can't read the prior token — Rick has to re-paste
// it through the Debug menu every build. The fix is a stable signing
// identity (Apple Developer ID), which is blocked on enrollment.
//
// Stopgap: persist the token in Application Support, scoped to bundle
// id, with 0600 perms. Bundle id is stable across rebuilds, so the
// token survives. When real signing lands, revert this file and the
// implementation goes back to using SecItem APIs.
//
// Public API (save/load/clear) is intentionally unchanged so call
// sites don't move. Type name is also unchanged for the same reason
// — it will be honest again post-revert.

import Foundation

enum KeychainTokenError: Error {
    case decodeFailed
    case ioFailed(Error)
}

struct KeychainTokenStore {
    static let shared = KeychainTokenStore()

    private let bundleScope = "ai.portablemind.md-editor"
    private let filename = "token.txt"

    private func storageURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent(bundleScope, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return dir.appendingPathComponent(filename)
    }

    /// Save (or overwrite) the bearer token. Empty strings are
    /// rejected — use `clear()` to remove.
    func save(token: String) throws {
        guard !token.isEmpty else {
            throw KeychainTokenError.decodeFailed
        }
        do {
            let url = try storageURL()
            try Data(token.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch let e as KeychainTokenError {
            throw e
        } catch {
            throw KeychainTokenError.ioFailed(error)
        }
    }

    /// Load the bearer token. Returns nil if no token has been saved
    /// (or if the entry was cleared). Throws only on unexpected
    /// errors.
    func load() throws -> String? {
        do {
            let url = try storageURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            let data = try Data(contentsOf: url)
            guard let token = String(data: data, encoding: .utf8) else {
                throw KeychainTokenError.decodeFailed
            }
            return token.isEmpty ? nil : token
        } catch let e as KeychainTokenError {
            throw e
        } catch {
            throw KeychainTokenError.ioFailed(error)
        }
    }

    /// Remove the token. Idempotent — no-op if nothing was saved.
    func clear() throws {
        do {
            let url = try storageURL()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch let e as KeychainTokenError {
            throw e
        } catch {
            throw KeychainTokenError.ioFailed(error)
        }
    }
}
