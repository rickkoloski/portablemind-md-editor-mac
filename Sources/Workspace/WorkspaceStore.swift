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

    /// D23 — pending Save As / New File request that drives the
    /// SaveAsSheet via `WorkspaceView.sheet(item:)`. nil → no sheet
    /// shown. Set by `requestSaveAs(for:)`; cleared by the sheet on
    /// dismiss.
    @Published var saveAsRequest: SaveAsRequest?

    /// D23 phase 4 — pending Rename request that drives the
    /// RenameSheet via `WorkspaceView.sheet(item:)`. Set by
    /// `requestRename(for:)`; cleared by the sheet on dismiss.
    @Published var renameRequest: RenameRequest?

    /// D23 phase 4 — payload for the RenameSheet. Carries the node
    /// being renamed plus its current name (prefilled in the field).
    struct RenameRequest: Identifiable {
        let id = UUID()
        let node: ConnectorNode
        var initialName: String { node.name }
    }

    /// D23 phase 5 — pending Move request driving MoveSheet.
    @Published var moveRequest: MoveRequest?

    /// D23 phase 5 — payload for MoveSheet. Carries the node being
    /// moved; the sheet's tree picker uses node.connector to know
    /// which tree to show.
    struct MoveRequest: Identifiable {
        let id = UUID()
        let node: ConnectorNode
    }

    /// D23.1 — pending Create Folder request driving CreateDirectorySheet.
    @Published var createDirectoryRequest: CreateDirectoryRequest?

    struct CreateDirectoryRequest: Identifiable {
        let id = UUID()
        let parent: ConnectorNode
    }

    /// D23 — payload for the SaveAsSheet. Carries the document being
    /// saved and the connector to default the picker to. `intent`
    /// distinguishes "save existing buffer to a new location" from
    /// "create a new empty file" — phase 3 sets `.newFile` for the
    /// New File flow.
    struct SaveAsRequest: Identifiable {
        let id = UUID()
        /// The document being Save-As'd. nil for `intent == .newFile`
        /// (the new file's content starts empty; no source document).
        let document: EditorDocument?
        let initialFilename: String
        let initialConnector: any Connector
        let intent: Intent
        enum Intent { case saveAs, newFile }
    }

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

    // MARK: - D23 Save As / New File

    /// Open the Save As sheet for `doc`. Picker defaults to the doc's
    /// origin connector (PM tab → its PortableMindConnector;
    /// Local tab → LocalConnector). If no matching connector is loaded,
    /// falls back to the first available connector (rare).
    func requestSaveAs(for doc: EditorDocument) {
        let connector = matchingConnector(for: doc)
            ?? connectors.first
        guard let connector else { return }
        let initialName = doc.connectorNode?.name
            ?? doc.url?.lastPathComponent
            ?? "Untitled.md"
        saveAsRequest = SaveAsRequest(
            document: doc,
            initialFilename: initialName,
            initialConnector: connector,
            intent: .saveAs)
    }

    /// D23 — dismiss the Save As sheet (called by the sheet on Cancel
    /// or successful Save).
    func dismissSaveAs() {
        saveAsRequest = nil
    }

    /// D23 phase 3 — open the SaveAsSheet in `newFile` mode. Picker
    /// defaults to the first PortableMindConnector (PM is the primary
    /// target for "New …"); falls back to the first available
    /// connector if no PM is loaded. The new file starts with an
    /// empty buffer; on Save the modal calls
    /// `PMFileOperations.newFile(in:name:store:)` which opens it as
    /// a new tab.
    func requestNewFile() {
        let connector = connectors.first(where: { $0 is PortableMindConnector })
            ?? connectors.first
        guard let connector else { return }
        saveAsRequest = SaveAsRequest(
            document: nil,
            initialFilename: "Untitled.md",
            initialConnector: connector,
            intent: .newFile)
    }

    private func matchingConnector(for doc: EditorDocument) -> (any Connector)? {
        switch doc.origin {
        case .local:
            return connectors.first { $0 is LocalConnector }
        case .portableMind(let connectorID, _, _):
            return connectors.first { $0.id == connectorID }
        }
    }

    /// D23 phase 4 — open the RenameSheet for `node`. Picker not
    /// involved (rename is in-place). The sheet calls
    /// `PMFileOperations.rename(node:to:store:)` on Save.
    func requestRename(for node: ConnectorNode) {
        renameRequest = RenameRequest(node: node)
    }

    func dismissRename() {
        renameRequest = nil
    }

    /// D23 phase 5 — open the MoveSheet for `node`. The sheet's tree
    /// picker uses node.connector's tree view-model. On Save the
    /// modal calls `PMFileOperations.move(node:to:store:)`.
    func requestMove(for node: ConnectorNode) {
        moveRequest = MoveRequest(node: node)
    }

    func dismissMove() {
        moveRequest = nil
    }

    /// D23.1 — open the CreateDirectorySheet under `parent`. On Save
    /// the modal calls `PMFileOperations.createDirectory(in:name:store:)`.
    func requestCreateDirectory(in parent: ConnectorNode) {
        createDirectoryRequest = CreateDirectoryRequest(parent: parent)
    }

    func dismissCreateDirectory() {
        createDirectoryRequest = nil
    }
}
