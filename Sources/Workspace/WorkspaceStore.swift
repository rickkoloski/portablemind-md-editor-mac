import AppKit
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

    /// D25 — transient scroll-target for "Reveal in File Tree". The
    /// sidebar's `ScrollViewReader` observes this via `.onChange` and
    /// scrolls to the matching row, then clears via `clearReveal()`.
    /// String form is the connector-qualified node id (matches the row's
    /// ForEach identity in `ConnectorTreeView`).
    @Published var pendingRevealNodeID: String?

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

    // MARK: - D25 Reveal in File Tree

    /// Expand sidebar ancestors of `document`'s file and scroll the tree
    /// to its row. If the file isn't under any currently-loaded
    /// connector tree, surfaces a stock NSAlert ("This file is outside
    /// currently open directories") with the full path.
    ///
    /// Sequence:
    /// 1. Resolve which connector / view-model owns this document and
    ///    compute the target node id + ancestor path list.
    /// 2. `await viewModel.expand(path:)` for each ancestor in
    ///    root-to-parent order. PortableMind expansion is async (chains
    ///    through `connector.children(of:)`); Local is sync but
    ///    serialised through the same API.
    /// 3. Brief `Task.sleep` so SwiftUI can render the freshly-expanded
    ///    rows before the scroll target is published — `proxy.scrollTo`
    ///    only finds rows that are already in the rendered tree.
    /// 4. Set `pendingRevealNodeID`; the sidebar's `.onChange(of:)`
    ///    consumes it.
    func revealInTree(document: EditorDocument) async {
        guard let target = resolveRevealTarget(for: document) else {
            outsideTreeAlert(for: document)
            return
        }
        for ancestor in target.ancestorPaths {
            await target.viewModel.expand(path: ancestor)
        }
        // Let SwiftUI lay out the newly-expanded rows before publishing
        // the scroll target. 50ms is empirical headroom; if a deeply
        // nested path proves brittle we can move to a `.task(id:)`
        // sidebar modifier so the scroll runs after the body re-evaluates.
        try? await Task.sleep(nanoseconds: 50_000_000)
        pendingRevealNodeID = target.nodeID
    }

    func clearReveal() {
        pendingRevealNodeID = nil
    }

    private struct RevealTarget {
        let viewModel: ConnectorTreeViewModel
        let nodeID: String
        /// Ancestor paths from connector root down to (but not
        /// including) the file itself. Order matters: top-down so each
        /// expansion's children are loaded before the next ancestor's
        /// path is checked.
        let ancestorPaths: [String]
    }

    private func resolveRevealTarget(for document: EditorDocument) -> RevealTarget? {
        switch document.origin {
        case .local:
            guard let url = document.url else { return nil }
            guard let local = connectors.first(where: { $0.id == "local" }),
                  let model = treeViewModels[local.id]
            else { return nil }
            let rootPath = local.rootNode.path
            // File must be at or under the workspace root.
            guard url.path == rootPath
                    || url.path.hasPrefix(rootPath + "/") else { return nil }
            return RevealTarget(
                viewModel: model,
                nodeID: "local:\(url.path)",
                ancestorPaths: ancestorPathsFromRoot(
                    rootPath: rootPath,
                    nodePath: url.path,
                    separator: "/"))

        case .portableMind(let connectorID, _, let displayPath):
            guard let pm = connectors.first(where: { $0.id == connectorID }),
                  let model = treeViewModels[pm.id],
                  let node = document.connectorNode
            else { return nil }
            let rootPath = pm.rootNode.path  // "" for PortableMind
            return RevealTarget(
                viewModel: model,
                nodeID: node.id,
                ancestorPaths: ancestorPathsFromRoot(
                    rootPath: rootPath,
                    nodePath: displayPath,
                    separator: "/"))
        }
    }

    /// Build the ancestor list from `rootPath` down to (but not
    /// including) `nodePath`. Both paths use `separator`; PortableMind's
    /// rootPath is the empty string so the first ancestor is `""` and
    /// each subsequent ancestor is `/seg1`, `/seg1/seg2`, ...
    /// Local's rootPath is absolute (`/Users/...`) so ancestors are
    /// `/Users/...`, `/Users/.../seg1`, `/Users/.../seg1/seg2`, ...
    private func ancestorPathsFromRoot(rootPath: String,
                                       nodePath: String,
                                       separator: Character) -> [String] {
        var ancestors: [String] = [rootPath]
        // Strip the root prefix so we can walk components below it.
        let relative: String
        if rootPath.isEmpty {
            relative = nodePath
        } else if nodePath == rootPath {
            return ancestors
        } else if nodePath.hasPrefix(rootPath + String(separator)) {
            relative = String(nodePath.dropFirst(rootPath.count + 1))
        } else {
            // Not under root — caller already validated, but stay safe.
            return ancestors
        }
        let segments = relative
            .split(separator: separator, omittingEmptySubsequences: true)
            .map(String.init)
        // Drop the file's own name; only intermediate dirs need expansion.
        let dirSegments = segments.dropLast()
        var accumulated = rootPath
        for segment in dirSegments {
            if accumulated.isEmpty {
                accumulated = "\(separator)\(segment)"
            } else if accumulated == String(separator) {
                accumulated = "\(separator)\(segment)"
            } else {
                accumulated = "\(accumulated)\(separator)\(segment)"
            }
            ancestors.append(accumulated)
        }
        return ancestors
    }

    private func outsideTreeAlert(for document: EditorDocument) {
        let alert = NSAlert()
        alert.messageText = "This file is outside currently open directories"
        alert.informativeText = PathFormatting.absolutePathForCopy(document)
            ?? document.displayName
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - D30 Session interest lifecycle

    /// Scope of a release operation — one file, or all docs the
    /// session is interested in.
    enum ReleaseScope {
        case file(URL)
        case all
    }

    /// Register a session as interested in `doc`. Phase 2 is a stub
    /// that records the signal; Phase 3 mutates
    /// `doc.interestedSessions` and enforces the v1 1:1 cap.
    func registerInterest(sessionID: String, on doc: EditorDocument, label: String? = nil) {
        NSLog("D30 registerInterest(sessionID: \(sessionID), on: \(doc.displayName), label: \(label ?? "nil")) — stub (Phase 3)")
    }

    /// Release a session's interest. Phase 2 is a stub; Phase 3
    /// iterates open tabs and clears matching `SessionInterest`
    /// entries.
    func releaseInterest(sessionID: String, scope: ReleaseScope) {
        NSLog("D30 releaseInterest(sessionID: \(sessionID), scope: \(scope)) — stub (Phase 3)")
    }
}
