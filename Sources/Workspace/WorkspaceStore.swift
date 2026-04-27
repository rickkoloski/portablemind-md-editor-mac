import Combine
import Foundation

/// The workspace — top-level observable owning the active connectors,
/// their tree view-models, and the tab store. Holds the security-
/// scoped access for the duration of the workspace and re-persists
/// state (workspace bookmark, open tabs, focused tab) as it changes.
@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published var rootURL: URL?

    /// Active connectors. Computed by `reconcileConnectors()` from the
    /// current `rootURL` (Local) and Keychain token presence
    /// (PortableMind). D19 will replace the keychain-presence
    /// heuristic with a connection-management UX.
    @Published private(set) var connectors: [any Connector] = []

    /// One view-model per connector, keyed by `connector.id`. Holds
    /// expansion state, async-loaded children, loading flags,
    /// per-path errors. Recreated when `connectors` changes.
    @Published private(set) var treeViewModels: [String: ConnectorTreeViewModel] = [:]

    let tabs = TabStore()

    private var bookmarkAccessStop: (() -> Void)?
    private var treeWatcher: FolderTreeWatcher?
    private var cancellables: Set<AnyCancellable> = []
    private var ready = false

    private static let openTabsKey = "openTabs"
    private static let focusedTabIndexKey = "focusedTabIndex"

    private init() {
        // Re-persist open tabs and focus whenever they change, so
        // next launch can restore.
        tabs.$documents
            .sink { [weak self] _ in self?.persistTabs() }
            .store(in: &cancellables)
        tabs.$focusedIndex
            .sink { [weak self] _ in self?.persistTabs() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Called from the SwiftUI scene `.onAppear`. Resolves any
    /// persisted workspace bookmark and re-opens the previous tab
    /// set.
    func restoreFromBookmarks() {
        if !ready,
           let resolved = try? SecurityScopedBookmarkStore.shared.resolve(
               key: SecurityScopedBookmarkKeys.workspaceRoot
           )
        {
            setRoot(url: resolved.url, stopAccessing: resolved.stopAccessing, persistBookmark: false)
        } else {
            // No persisted folder — still try to bring up a PM
            // connector if a token is present.
            reconcileConnectors()
        }
        restorePersistedTabs()
        ready = true
        CommandSurface.drainPending(in: self)
    }

    var isReady: Bool { ready }

    /// Switch (or set) the workspace root. Callers provide the
    /// `stopAccessing` closure from whichever layer started the
    /// scoped-resource access; we hold it until the root changes
    /// again or the app quits.
    func setRoot(url: URL,
                 stopAccessing: (() -> Void)? = nil,
                 persistBookmark: Bool = true) {
        bookmarkAccessStop?()
        bookmarkAccessStop = stopAccessing

        rootURL = url

        treeWatcher = FolderTreeWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.reconcileConnectors() }
        }

        if persistBookmark {
            try? SecurityScopedBookmarkStore.shared.save(
                url: url,
                forKey: SecurityScopedBookmarkKeys.workspaceRoot
            )
        }
        reconcileConnectors()
    }

    /// Rebuild the connectors array from current state:
    /// - LocalConnector if `rootURL` is set.
    /// - PortableMindConnector if a bearer token is present in the
    ///   Keychain.
    ///
    /// Called from setRoot, restoreFromBookmarks, the FolderTree
    /// watcher (external changes), and the Debug menu's token
    /// set/clear so the sidebar reacts to either workspace-root or
    /// token-presence changes without a relaunch.
    func reconcileConnectors() {
        var list: [any Connector] = []
        if let url = rootURL {
            list.append(LocalConnector(rootURL: url))
        }
        // `try?` flattens nested optionals — load() returns String?
        // and try? produces String? (nil on either throw or absent).
        if let token = try? KeychainTokenStore.shared.load(), !token.isEmpty {
            list.append(PortableMindConnector())
        }
        connectors = list

        // Rebuild view-models. Drop ones whose connector is gone;
        // create fresh ones for new connectors. (Future: preserve
        // expansion state across reconciliations by keying on
        // connector.id.)
        var models: [String: ConnectorTreeViewModel] = [:]
        for connector in list {
            models[connector.id] = ConnectorTreeViewModel(connector: connector)
        }
        treeViewModels = models
    }

    // MARK: - Tab persistence

    private func persistTabs() {
        let paths = tabs.documents.compactMap { $0.url?.path }
        UserDefaults.standard.set(paths, forKey: Self.openTabsKey)
        UserDefaults.standard.set(tabs.focusedIndex ?? -1, forKey: Self.focusedTabIndexKey)
    }

    private func restorePersistedTabs() {
        let paths = (UserDefaults.standard.array(forKey: Self.openTabsKey) as? [String]) ?? []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = tabs.open(fileURL: url)
            }
        }
        let focusedIndex = UserDefaults.standard.integer(forKey: Self.focusedTabIndexKey)
        if focusedIndex >= 0, focusedIndex < tabs.documents.count {
            tabs.focusedIndex = focusedIndex
        }
    }
}
