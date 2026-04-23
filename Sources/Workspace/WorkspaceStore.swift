import Combine
import Foundation

/// The workspace — top-level observable owning the current root
/// folder, the tree model, and the tab store. Holds the security-
/// scoped access for the duration of the workspace and re-persists
/// state (workspace bookmark, open tabs, focused tab) as it changes.
@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published var rootURL: URL?
    @Published var rootNode: FolderNode?

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
        rootNode = FolderNode(url: url, name: url.lastPathComponent, isDirectory: true)

        treeWatcher = FolderTreeWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.refreshTreeRoot() }
        }

        if persistBookmark {
            try? SecurityScopedBookmarkStore.shared.save(
                url: url,
                forKey: SecurityScopedBookmarkKeys.workspaceRoot
            )
        }
    }

    /// Force a re-load of the root node — cheap way to trigger
    /// SwiftUI's OutlineGroup to re-query children. Called by the
    /// folder watcher on external changes.
    func refreshTreeRoot() {
        guard let url = rootURL else { return }
        // Assigning a fresh FolderNode (same URL) nudges SwiftUI.
        rootNode = FolderNode(url: url, name: url.lastPathComponent, isDirectory: true)
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
