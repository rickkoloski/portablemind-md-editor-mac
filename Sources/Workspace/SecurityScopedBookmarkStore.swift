import Foundation

/// Persists and resolves security-scoped bookmarks via UserDefaults.
/// Used by the workspace to retain access to a user-selected folder
/// across app launches without re-prompting, per engineering-
/// standards §1.1 (sandbox-safe source from day one) and the D6 spec
/// requirement that the workspace root persist.
///
/// The caller is responsible for balancing `startAccessing…` /
/// `stopAccessing…` — resolve() hands back a stop closure that the
/// caller must invoke when access is no longer needed.
@MainActor
final class SecurityScopedBookmarkStore {
    static let shared = SecurityScopedBookmarkStore()
    private init() {}

    /// Save the bookmark for `url` under `key`. Overwrites any
    /// previous value.
    func save(url: URL, forKey key: String) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Resolve the bookmark stored under `key`, start access, and
    /// return the URL with a balancing stop closure. Returns nil if
    /// no bookmark is stored, the bookmark can't be resolved, or
    /// scoped access can't be started.
    func resolve(key: String) throws -> (url: URL, stopAccessing: () -> Void)? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            // Refresh silently if the resolved URL is still valid.
            try? save(url: url, forKey: key)
        }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return (url, { url.stopAccessingSecurityScopedResource() })
    }

    /// Drop a stored bookmark (e.g., the user has cleared the
    /// workspace selection).
    func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum SecurityScopedBookmarkKeys {
    static let workspaceRoot = "workspaceRootBookmark"
}
