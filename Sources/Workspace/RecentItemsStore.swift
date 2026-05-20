import Combine
import Foundation

/// D31 — durable store for the Open Recent menu (files + folders) and
/// the session-restore record (open tabs, focused tab, per-tab scroll
/// line). UserDefaults-backed JSON; schema-versioned so a forward-
/// incompatible payload reads as empty rather than crashing.
///
/// Two responsibilities live in one store on purpose: the menu lists
/// entries by ID and the session state references the same IDs, so
/// keeping them in one observable avoids drift between "what's in the
/// menu" and "what restores on launch."
///
/// Lifecycle:
/// - First `init` after upgrade migrates the legacy `openTabs` (`[String]`)
///   and `focusedTabIndex` (`Int`) UserDefaults keys into a v1
///   `SessionState`, then deletes them.
/// - `recordOpen(...)` is called from `WorkspaceStore` when a tab opens.
/// - `updateSessionState(openTabIDs:focusedTabID:)` is called when the
///   tab set or focus changes.
/// - `recordScrollLine(_:for:)` is called debounced from the editor
///   coordinator (Phase 3 wires this).
@MainActor
final class RecentItemsStore: ObservableObject {
    static let shared = RecentItemsStore()

    @Published private(set) var entries: [RecentEntry] = []      // newest first
    @Published private(set) var folders: [RecentFolderEntry] = []// newest first
    @Published private(set) var sessionState: SessionState = SessionState()

    static let maxEntries = 15
    static let maxFolders = 5

    // MARK: - UserDefaults keys

    private static let entriesKey = "ai.portablemind.md-editor.recent.entries.v1"
    private static let foldersKey = "ai.portablemind.md-editor.recent.folders.v1"
    private static let sessionKey = "ai.portablemind.md-editor.session.state.v1"

    /// Legacy keys from the pre-D31 partial persistence in
    /// `WorkspaceStore`. Migrated once on first post-upgrade init.
    fileprivate static let legacyOpenTabsKey = "openTabs"
    fileprivate static let legacyFocusedTabIndexKey = "focusedTabIndex"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Test seam — injects a fresh defaults suite so XCTests don't
    /// stomp on the user's real prefs.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
        migrateLegacyIfNeeded()
    }

    // MARK: - Recording

    /// Promote (or insert) a local file. Newest-first; cap honored.
    func recordOpen(localURL url: URL) {
        let path = url.path
        var list = entries
        if let i = list.firstIndex(where: { $0.matchesLocal(path: path) }) {
            var existing = list.remove(at: i)
            existing.addedAt = Date()
            list.insert(existing, at: 0)
        } else {
            let entry = RecentEntry(
                id: UUID(),
                addedAt: Date(),
                kind: .local(path: path))
            list.insert(entry, at: 0)
        }
        if list.count > Self.maxEntries {
            list = Array(list.prefix(Self.maxEntries))
        }
        entries = list
        persistEntries()
    }

    /// Promote (or insert) a PortableMind file. Identity: (connectorID, fileID).
    func recordOpen(connectorID: String,
                    fileID: Int,
                    displayPath: String,
                    name: String,
                    lastSeenUpdatedAt: Date?) {
        var list = entries
        if let i = list.firstIndex(where: { $0.matchesPM(connectorID: connectorID, fileID: fileID) }) {
            var existing = list.remove(at: i)
            existing.addedAt = Date()
            // Refresh display fields — name/path/lastSeen may have changed
            // server-side since the last record.
            if case .portableMind = existing.kind {
                existing.kind = .portableMind(
                    connectorID: connectorID,
                    fileID: fileID,
                    displayPath: displayPath,
                    name: name,
                    lastSeenUpdatedAt: lastSeenUpdatedAt)
            }
            list.insert(existing, at: 0)
        } else {
            let entry = RecentEntry(
                id: UUID(),
                addedAt: Date(),
                kind: .portableMind(
                    connectorID: connectorID,
                    fileID: fileID,
                    displayPath: displayPath,
                    name: name,
                    lastSeenUpdatedAt: lastSeenUpdatedAt))
            list.insert(entry, at: 0)
        }
        if list.count > Self.maxEntries {
            list = Array(list.prefix(Self.maxEntries))
        }
        entries = list
        persistEntries()
    }

    /// Promote (or insert) a workspace-root folder. Cap 5.
    func recordFolder(_ url: URL) {
        let path = url.path
        var list = folders
        if let i = list.firstIndex(where: { $0.path == path }) {
            var existing = list.remove(at: i)
            existing.addedAt = Date()
            list.insert(existing, at: 0)
        } else {
            list.insert(RecentFolderEntry(path: path, addedAt: Date()), at: 0)
        }
        if list.count > Self.maxFolders {
            list = Array(list.prefix(Self.maxFolders))
        }
        folders = list
        persistFolders()
    }

    // MARK: - Lookup

    func entry(for id: UUID) -> RecentEntry? {
        entries.first { $0.id == id }
    }

    /// Resolve a `RecentEntry.id` from a local URL. Used by the scroll-
    /// line writer in Phase 3.
    func entryID(forLocalURL url: URL) -> UUID? {
        entries.first { $0.matchesLocal(path: url.path) }?.id
    }

    /// Resolve a `RecentEntry.id` from a PM (connectorID, fileID).
    func entryID(forPMConnectorID connectorID: String, fileID: Int) -> UUID? {
        entries.first { $0.matchesPM(connectorID: connectorID, fileID: fileID) }?.id
    }

    // MARK: - Clear

    /// Wipe MRU + folders + session in one shot. Bound to "Clear Menu".
    func clear() {
        entries = []
        folders = []
        sessionState = SessionState()
        defaults.removeObject(forKey: Self.entriesKey)
        defaults.removeObject(forKey: Self.foldersKey)
        defaults.removeObject(forKey: Self.sessionKey)
    }

    // MARK: - Session state

    /// Phase 2/4 — caller passes the current ordered tab IDs and focus.
    /// IDs must be from this store (no auto-record happens here).
    func updateSessionState(openTabIDs: [UUID], focusedTabID: UUID?) {
        var s = sessionState
        s.openTabs = openTabIDs
        s.focusedTab = focusedTabID
        // Prune scroll lines for tabs no longer open.
        let alive = Set(openTabIDs)
        s.scrollLines = s.scrollLines.filter { alive.contains($0.key) }
        sessionState = s
        persistSession()
    }

    /// Phase 3 — record first-visible scroll line. Caller is expected
    /// to debounce; this method is unconditional.
    func recordScrollLine(_ line: Int, for entryID: UUID) {
        var s = sessionState
        s.scrollLines[entryID] = max(1, line)
        sessionState = s
        persistSession()
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: Self.entriesKey),
           let decoded = try? decoder.decode([RecentEntry].self, from: data) {
            entries = decoded
        }
        if let data = defaults.data(forKey: Self.foldersKey),
           let decoded = try? decoder.decode([RecentFolderEntry].self, from: data) {
            folders = decoded
        }
        if let data = defaults.data(forKey: Self.sessionKey),
           let decoded = try? decoder.decode(SessionState.self, from: data),
           decoded.schemaVersion == SessionState.currentSchemaVersion {
            sessionState = decoded
        }
        // Unknown / forward schemaVersion → silently keep defaults.
    }

    private func persistEntries() {
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: Self.entriesKey)
        }
    }

    private func persistFolders() {
        if let data = try? encoder.encode(folders) {
            defaults.set(data, forKey: Self.foldersKey)
        }
    }

    private func persistSession() {
        if let data = try? encoder.encode(sessionState) {
            defaults.set(data, forKey: Self.sessionKey)
        }
    }

    // MARK: - Legacy migration

    /// Reads the pre-D31 `openTabs` / `focusedTabIndex` keys (if present)
    /// and folds them into a v1 SessionState whose entries point at local
    /// files that still exist. Missing files are dropped silently. Legacy
    /// keys are deleted after migration regardless of outcome so the
    /// next launch is a no-op.
    private func migrateLegacyIfNeeded() {
        let hasLegacy = defaults.object(forKey: Self.legacyOpenTabsKey) != nil
            || defaults.object(forKey: Self.legacyFocusedTabIndexKey) != nil
        guard hasLegacy else { return }

        defer {
            defaults.removeObject(forKey: Self.legacyOpenTabsKey)
            defaults.removeObject(forKey: Self.legacyFocusedTabIndexKey)
        }

        let paths = (defaults.array(forKey: Self.legacyOpenTabsKey) as? [String]) ?? []
        let legacyFocusIndex = defaults.object(forKey: Self.legacyFocusedTabIndexKey) as? Int

        // Don't backfill MRU entries for the legacy state — the old store
        // had no MRU concept, so retroactively materializing entries
        // would lie about "recent" history. Only create the entries we
        // need to express the open-tab list.
        //
        // Track (originalIndex → newEntryID) so the legacy focusedTabIndex
        // (which indexed into the ORIGINAL paths array, before any
        // missing-file drops) can be remapped to the surviving entry
        // even if intervening tabs were dropped.
        var migratedTabIDs: [UUID] = []
        var migratedEntries: [RecentEntry] = []
        var originalIndexToNewID: [Int: UUID] = [:]
        for (originalIndex, path) in paths.enumerated() {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let entry = RecentEntry(
                id: UUID(),
                addedAt: Date(),
                kind: .local(path: url.path))
            migratedEntries.append(entry)
            migratedTabIDs.append(entry.id)
            originalIndexToNewID[originalIndex] = entry.id
        }
        guard !migratedTabIDs.isEmpty else { return }

        // Prepend migrated entries to MRU (cap honored), preserving any
        // entries we already loaded (none expected on a true first
        // upgrade, but harmless on a re-migration edge).
        var combined = migratedEntries
        for existing in entries where !combined.contains(where: { $0.id == existing.id }) {
            combined.append(existing)
        }
        if combined.count > Self.maxEntries {
            combined = Array(combined.prefix(Self.maxEntries))
        }
        entries = combined
        persistEntries()

        // Map legacy focusedIndex (in original `paths` ordering, with -1
        // sentinel) to a UUID via the originalIndex map. If the focused
        // tab was the one dropped for missing-file, focus becomes nil
        // (the user's chosen tab is gone — don't silently jump them
        // somewhere else).
        let focusedTabID: UUID? = {
            guard let idx = legacyFocusIndex, idx >= 0 else { return nil }
            return originalIndexToNewID[idx]
        }()

        var s = SessionState()
        s.openTabs = migratedTabIDs
        s.focusedTab = focusedTabID
        sessionState = s
        persistSession()
    }
}

// MARK: - Types

/// A file the user has opened. The kind discriminates local vs PM
/// because the two have different identity rules and re-open paths.
struct RecentEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var addedAt: Date
    var kind: Kind

    enum Kind: Codable, Hashable {
        case local(path: String)
        case portableMind(
            connectorID: String,
            fileID: Int,
            displayPath: String,
            name: String,
            lastSeenUpdatedAt: Date?
        )
    }

    /// File-name for menu display. POSIX basename for local; PM `name`
    /// field for PM.
    var displayName: String {
        switch kind {
        case .local(let path):
            return (path as NSString).lastPathComponent
        case .portableMind(_, _, _, let name, _):
            return name
        }
    }

    /// Whether the entry can be opened right now. Local: the file
    /// exists at the recorded path. PM: a connector with the matching
    /// id is loaded. Used by the menu to render the entry disabled.
    @MainActor
    func isAvailable(connectors: [any Connector]) -> Bool {
        switch kind {
        case .local(let path):
            return FileManager.default.fileExists(atPath: path)
        case .portableMind(let cid, _, _, _, _):
            return connectors.contains { $0.id == cid }
        }
    }

    /// Tooltip shown on the menu item — full identifier for the file.
    /// Home-relative for local paths (mirrors D21 tooltip convention).
    var tooltip: String {
        switch kind {
        case .local(let path):
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if path.hasPrefix(home) {
                return "~" + path.dropFirst(home.count)
            }
            return path
        case .portableMind(let cid, _, let displayPath, _, _):
            return "\(displayPath)  ·  \(cid)"
        }
    }

    /// Stable connector key for `entryID(for…)` lookups.
    fileprivate func matchesLocal(path: String) -> Bool {
        if case .local(let p) = kind { return p == path }
        return false
    }

    fileprivate func matchesPM(connectorID: String, fileID: Int) -> Bool {
        if case .portableMind(let cid, let fid, _, _, _) = kind {
            return cid == connectorID && fid == fileID
        }
        return false
    }
}

/// A workspace-root folder the user has opened.
struct RecentFolderEntry: Codable, Hashable {
    let path: String
    var addedAt: Date

    /// Last path component for the menu label.
    var displayName: String {
        (path as NSString).lastPathComponent
    }

    /// Home-relative tooltip (mirrors D21 convention).
    var tooltip: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Folder still resolves on disk?
    var isAvailable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

/// What was open at quit. Referenced by `RecentEntry.id` so the menu
/// list and the restore list never drift.
struct SessionState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = SessionState.currentSchemaVersion
    var openTabs: [UUID] = []
    var focusedTab: UUID? = nil
    var scrollLines: [UUID: Int] = [:]
}
