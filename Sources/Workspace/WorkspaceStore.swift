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

    /// D31 phase 2 — set of `EditorDocument.id` seen on the previous
    /// `tabs.$documents` emission. Used to detect newly-opened docs
    /// without re-recording on every focus change.
    private var seenDocumentIDs: Set<UUID> = []

    /// D31 phase 4 — when true, the documents-changed subscription
    /// skips MRU recording AND session-state persistence so restore
    /// doesn't re-promote rehydrated tabs or partial-persist a half-
    /// restored snapshot. Set by `restoreSession()`; cleared once
    /// restore finishes.
    private var isRestoring = false

    private init() {
        // D31 phase 4 — single sink: record any newly-opened doc, then
        // persist current session state. Order matters: persistSession
        // resolves doc → RecentEntry.id, so the entry must exist first.
        tabs.$documents
            .sink { [weak self] docs in
                guard let self else { return }
                self.recordNewlyOpenedDocuments(docs)
                self.persistSessionState()
            }
            .store(in: &cancellables)
        tabs.$focusedIndex
            .sink { [weak self] _ in self?.persistSessionState() }
            .store(in: &cancellables)
    }

    private func recordNewlyOpenedDocuments(_ docs: [EditorDocument]) {
        if isRestoring { return }
        let currentIDs = Set(docs.map(\.id))
        let newIDs = currentIDs.subtracting(seenDocumentIDs)
        for doc in docs where newIDs.contains(doc.id) {
            recordOpenInRecents(doc)
        }
        seenDocumentIDs = currentIDs
    }

    /// D31 phase 4 — translate the live tab list into RecentEntry IDs and
    /// hand off to RecentItemsStore.
    private func persistSessionState() {
        if isRestoring { return }
        let tabIDs: [UUID] = tabs.documents.compactMap { recentEntryID(for: $0) }
        let focusedID: UUID? = {
            guard let focusedIdx = tabs.focusedIndex,
                  tabs.documents.indices.contains(focusedIdx) else { return nil }
            return recentEntryID(for: tabs.documents[focusedIdx])
        }()
        RecentItemsStore.shared.updateSessionState(
            openTabIDs: tabIDs, focusedTabID: focusedID)
    }

    /// Resolve the RecentEntry.id that backs an open EditorDocument, or
    /// nil for documents that can't be expressed as a RecentEntry
    /// (untitled local buffers, etc).
    private func recentEntryID(for doc: EditorDocument) -> UUID? {
        switch doc.origin {
        case .local:
            guard let url = doc.url else { return nil }
            return RecentItemsStore.shared.entryID(forLocalURL: url)
        case let .portableMind(connectorID, fileID, _):
            return RecentItemsStore.shared.entryID(
                forPMConnectorID: connectorID, fileID: fileID)
        }
    }

    /// D31 phase 3 — editor coordinator calls this (debounced 500ms) with
    /// the first-visible line for a focused tab. We resolve the matching
    /// `RecentEntry.id` from the doc's origin and forward to the store.
    /// A doc with no matching entry (e.g. untitled local buffer) is a
    /// silent no-op.
    func sessionScrollLineDidChange(docID: UUID, line: Int) {
        guard let doc = tabs.documents.first(where: { $0.id == docID }) else { return }
        let entryID: UUID?
        switch doc.origin {
        case .local:
            guard let url = doc.url else { return }
            entryID = RecentItemsStore.shared.entryID(forLocalURL: url)
        case let .portableMind(connectorID, fileID, _):
            entryID = RecentItemsStore.shared.entryID(
                forPMConnectorID: connectorID, fileID: fileID)
        }
        guard let id = entryID else { return }
        RecentItemsStore.shared.recordScrollLine(line, for: id)
    }

    private func recordOpenInRecents(_ doc: EditorDocument) {
        switch doc.origin {
        case .local:
            // Untitled local buffers have no url — nothing to record.
            guard let url = doc.url else { return }
            RecentItemsStore.shared.recordOpen(localURL: url)
        case let .portableMind(connectorID, fileID, displayPath):
            let name = doc.connectorNode?.name
                ?? (displayPath as NSString).lastPathComponent
            RecentItemsStore.shared.recordOpen(
                connectorID: connectorID,
                fileID: fileID,
                displayPath: displayPath,
                name: name,
                lastSeenUpdatedAt: doc.connectorNode?.lastSeenUpdatedAt)
        }
    }

    // MARK: - Lifecycle

    /// Called from the SwiftUI scene `.onAppear`. Resolves any
    /// persisted workspace bookmark and re-opens the previous tab set.
    /// D31 phase 4 — tab restore now goes through RecentItemsStore's
    /// SessionState. PM tabs are restored async (the connector fetch
    /// resolves over the network); local tabs are restored synchronously
    /// so the bulk of the UI is in place before the first runloop hop.
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
        restoreSession()
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
            // D31 phase 2 — record in Recent Folders. Only when the user
            // actually chose this root (persistBookmark=true skips the
            // restore path, which is just rehydrating the prior root).
            RecentItemsStore.shared.recordFolder(url)
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

    // MARK: - D31 phase 4 — Session restore

    /// Rehydrate the previous session's tabs (local + PM), focus, and
    /// scroll lines from `RecentItemsStore.sessionState`. Sets
    /// `isRestoring` so the doc-set / focus subscriptions don't re-
    /// promote rehydrated tabs in MRU or persist partial snapshots.
    /// Local tabs open synchronously; PM tabs open async (one Task per
    /// PM tab, parallel) and the post-fetch op re-runs focus + scroll
    /// assignment in case the focused tab was PM.
    private func restoreSession() {
        let session = RecentItemsStore.shared.sessionState
        guard !session.openTabs.isEmpty else { return }

        isRestoring = true

        // Map from RecentEntry.id → EditorDocument.id once tabs land,
        // so we can resolve focus / scroll-line by entry id even when
        // some tabs arrive async.
        var entryToDocID: [UUID: UUID] = [:]
        var pendingPMRestores = 0

        let applyFocusAndScroll: () -> Void = { [weak self] in
            guard let self else { return }
            if let focusEntryID = session.focusedTab,
               let docID = entryToDocID[focusEntryID],
               let idx = self.tabs.documents.firstIndex(where: { $0.id == docID }) {
                self.tabs.focusedIndex = idx
            }
            for (entryID, line) in session.scrollLines {
                guard let docID = entryToDocID[entryID],
                      let doc = self.tabs.documents.first(where: { $0.id == docID })
                else { continue }
                doc.pendingFocusTarget = .caret(line: line, column: 0)
            }
        }

        for entryID in session.openTabs {
            guard let entry = RecentItemsStore.shared.entry(for: entryID) else { continue }
            switch entry.kind {
            case let .local(path):
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                if let doc = tabs.open(fileURL: url) {
                    entryToDocID[entryID] = doc.id
                }
            case let .portableMind(connectorID, fileID, displayPath, name, lastSeenUpdatedAt):
                guard let connector = connectors.first(where: { $0.id == connectorID }) else {
                    continue   // F12 / spec §2: connector not loaded → silent skip
                }
                pendingPMRestores += 1
                let node = ConnectorNode(
                    id: "\(connectorID):file:\(fileID)",
                    name: name,
                    path: displayPath,
                    kind: .file,
                    isSupported: true,
                    lastSeenUpdatedAt: lastSeenUpdatedAt,
                    connector: connector)
                Task { @MainActor [weak self, entryID] in
                    defer {
                        pendingPMRestores -= 1
                        if pendingPMRestores == 0 {
                            applyFocusAndScroll()
                            self?.isRestoring = false
                            self?.seenDocumentIDs = Set(self?.tabs.documents.map(\.id) ?? [])
                        }
                    }
                    guard let self else { return }
                    do {
                        let (bytes, refreshedNode) = try await connector.openFile(node)
                        let text = String(data: bytes, encoding: .utf8) ?? ""
                        let doc = self.tabs.openFromConnector(content: text, node: refreshedNode)
                        entryToDocID[entryID] = doc.id
                    } catch {
                        // F12 — silent skip on restore failure; the MRU
                        // entry stays (next menu rebuild reflects state).
                    }
                }
            }
        }

        // Sync portion done. If no PM restores were queued, apply focus
        // + scroll now; otherwise the last PM completion does it.
        seenDocumentIDs = Set(tabs.documents.map(\.id))
        if pendingPMRestores == 0 {
            applyFocusAndScroll()
            isRestoring = false
            // One persist now to capture the restored session state in
            // canonical form (entries unchanged; this normalizes any
            // dropped tabs out of the SessionState).
            persistSessionState()
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

    /// Register a session as interested in `doc`. v1 1:1 cap means
    /// any prior interest on the doc is replaced.
    func registerInterest(sessionID: String, on doc: EditorDocument, label: String? = nil) {
        doc.setInterestedSession(SessionInterest.make(sessionID: sessionID, label: label))
    }

    /// Release a session's interest. `.file(URL)` matches any open
    /// tab whose `url.standardizedFileURL.path` equals the given
    /// URL's; `.all` removes the session from every open tab.
    func releaseInterest(sessionID: String, scope: ReleaseScope) {
        switch scope {
        case .all:
            for doc in tabs.documents {
                doc.removeInterestedSession(sessionID: sessionID)
            }
        case .file(let url):
            let target = url.standardizedFileURL.path
            for doc in tabs.documents {
                if let docPath = doc.url?.standardizedFileURL.path, docPath == target {
                    doc.removeInterestedSession(sessionID: sessionID)
                }
            }
        }
    }
}
