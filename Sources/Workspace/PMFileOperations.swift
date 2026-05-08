// D23 — shared file-management service that the SaveAsSheet UI AND the
// harness `pm_save_as` action both call. Centralizes the "create on
// connector + rebind the open tab" sequence so the modal and the
// harness can't drift in semantics.
//
// Design: enum-as-namespace, @MainActor for the document mutation step.
// All operations are async because the connector calls are.

import Foundation

@MainActor
enum PMFileOperations {

    /// Save `doc`'s current buffer as a new file at `parent / name`.
    ///
    /// Side effects (Q2 — switch existing tab to new node):
    /// - Calls `parent.connector.createFile(in: parent, name: name, bytes: doc.source)`.
    /// - Updates `doc.origin`, `doc.connectorNode`, and `doc.url` so the
    ///   open tab now points at the new file.
    /// - Sets `doc.lastSavedSource = doc.source` (no longer dirty).
    ///
    /// Returns the new node so callers can splice it into the sidebar
    /// tree. Throws `ConnectorError` on failure (the modal surfaces
    /// inline; the harness writes the error to its result file).
    static func saveAs(doc: EditorDocument,
                       to parent: ConnectorNode,
                       name: String) async throws -> ConnectorNode {
        let bytes = Data(doc.source.utf8)
        let newNode = try await parent.connector.createFile(
            in: parent, name: name, bytes: bytes)

        let (newOrigin, newURL) = mapNodeToOrigin(
            newNode, parentConnector: parent.connector)
        doc.updateAfterSaveAs(
            newOrigin: newOrigin,
            newConnectorNode: newNode,
            newURL: newURL)
        // D23.1 — splice into the cached tree so the sidebar
        // refreshes without manual reload (closes TODO-D23-tree-splice).
        // Also handled in the WorkspaceStore-aware overload below.
        return newNode
    }

    /// D23 phase 2 + D23.1 splice — saveAs variant that takes the
    /// store so it can splice the new node into the cached tree.
    /// Prefer this in modal/harness paths; the older `saveAs(doc:to:name:)`
    /// stays for compatibility but doesn't splice.
    @discardableResult
    static func saveAs(doc: EditorDocument,
                       to parent: ConnectorNode,
                       name: String,
                       store: WorkspaceStore) async throws -> ConnectorNode {
        let newNode = try await saveAs(doc: doc, to: parent, name: name)
        if let vm = store.treeViewModels[parent.connector.id] {
            vm.upsertNode(newNode, parentPath: parent.path)
        }
        return newNode
    }

    /// D23 phase 3 — create a new empty file at `parent / name` and
    /// open it as a new tab in `store.tabs`. Different from `saveAs`
    /// in that this doesn't operate on an existing buffer — the new
    /// tab starts empty and the user types into it.
    ///
    /// Returns the new node so callers can splice it into the sidebar
    /// tree (Q7 follow-up).
    @discardableResult
    static func newFile(in parent: ConnectorNode,
                        name: String,
                        store: WorkspaceStore) async throws -> ConnectorNode {
        let newNode = try await parent.connector.createFile(
            in: parent, name: name, bytes: Data())
        // openFromConnector handles origin construction, isReadOnly
        // (from connector.canWrite), de-dupe, and focus. Empty source
        // for a brand-new file.
        _ = store.tabs.openFromConnector(content: "", node: newNode)
        // D23.1 — splice into the cached tree.
        if let vm = store.treeViewModels[parent.connector.id] {
            vm.upsertNode(newNode, parentPath: parent.path)
        }
        return newNode
    }

    /// D23 phase 4 — rename `node` to `newName` in its current parent
    /// directory. Returns the refreshed node from the server. Side
    /// effects:
    /// - Calls `node.connector.renameFile(node, to: newName)`.
    /// - For any open tab whose `connectorNode.id` matches, updates
    ///   `origin.displayPath` + `connectorNode` so the tab title
    ///   refreshes. Buffer / caret / scroll preserved (Q3).
    @discardableResult
    static func rename(node: ConnectorNode,
                       to newName: String,
                       store: WorkspaceStore) async throws -> ConnectorNode {
        let parentP = parentPath(of: node.path)
        let refreshed = try await node.connector.renameFile(node, to: newName)
        updateOpenTabs(matching: refreshed, in: store)
        // D23.1 — splice into the cached tree (rename keeps the same
        // parent; upsert by id replaces the old entry in place).
        if let vm = store.treeViewModels[node.connector.id] {
            vm.upsertNode(refreshed, parentPath: parentP)
        }
        return refreshed
    }

    /// D23 phase 5 — move `node` to a new parent directory. Returns the
    /// refreshed node. Same tab-update side effects as rename.
    @discardableResult
    static func move(node: ConnectorNode,
                     to newParent: ConnectorNode,
                     store: WorkspaceStore) async throws -> ConnectorNode {
        let oldParentPath = parentPath(of: node.path)
        let refreshed = try await node.connector.moveFile(
            node, to: newParent)
        updateOpenTabs(matching: refreshed, in: store)
        // Splice: remove from old parent, upsert under new parent.
        if let vm = store.treeViewModels[node.connector.id] {
            vm.removeNode(id: node.id, parentPath: oldParentPath)
            vm.upsertNode(refreshed, parentPath: newParent.path)
        }
        return refreshed
    }

    // MARK: - D23.1 destructive ops + directory create

    /// D23.1 — delete a file or directory. Hard delete (Q2). For files:
    /// closes any open tab whose connectorNode matches. For directories:
    /// closes any open tab whose connectorNode is inside the deleted
    /// directory (path prefix with trailing-/ boundary, Q4). Splices
    /// the cached tree to remove the node.
    static func delete(node: ConnectorNode,
                       store: WorkspaceStore) async throws {
        let nodeParentPath = parentPath(of: node.path)
        switch node.kind {
        case .file:
            try await node.connector.deleteFile(node)
            closeTabsForFile(nodeID: node.id, in: store)
        case .directory:
            try await node.connector.deleteDirectory(node)
            closeTabsInDirectory(path: node.path, in: store)
        }
        if let vm = store.treeViewModels[node.connector.id] {
            vm.removeNode(id: node.id, parentPath: nodeParentPath)
        }
    }

    /// D23.1 — create a new (empty) directory at `parent / name`.
    /// Returns the new directory node. Splices into the cached tree.
    @discardableResult
    static func createDirectory(in parent: ConnectorNode,
                                name: String,
                                store: WorkspaceStore) async throws -> ConnectorNode {
        let newNode = try await parent.connector.createDirectory(
            in: parent, name: name)
        if let vm = store.treeViewModels[parent.connector.id] {
            vm.upsertNode(newNode, parentPath: parent.path)
        }
        return newNode
    }

    /// Close any open tab whose connectorNode.id matches `nodeID`.
    /// Used by file delete.
    private static func closeTabsForFile(nodeID: String,
                                         in store: WorkspaceStore) {
        let docs = store.tabs.documents
        for doc in docs where doc.connectorNode?.id == nodeID {
            store.tabs.close(id: doc.id)
        }
    }

    /// Close any open tab whose connectorNode.path is the deleted
    /// directory's path or starts with `<dirPath>/` (Q4 — trailing-/
    /// boundary check so `/projects` deletion doesn't close
    /// `/projects-old` tabs).
    private static func closeTabsInDirectory(path dirPath: String,
                                             in store: WorkspaceStore) {
        let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
        let docs = store.tabs.documents
        for doc in docs {
            guard let nodePath = doc.connectorNode?.path else { continue }
            if nodePath == dirPath || nodePath.hasPrefix(prefix) {
                store.tabs.close(id: doc.id)
            }
        }
    }

    /// Strip the last path component from `path`. Used by mutation paths
    /// to know which `parentPath` to splice into. Connector paths use
    /// `/` separators regardless of platform.
    private static func parentPath(of path: String) -> String {
        if let idx = path.lastIndex(of: "/") {
            let parent = String(path[..<idx])
            return parent.isEmpty ? "/" : parent
        }
        return "/"
    }

    /// Walk every open tab; if any has `connectorNode.id == refreshed.id`,
    /// update its origin.displayPath + connectorNode in place. Used by
    /// rename + move to keep open tabs in sync after a server-side
    /// mutation that didn't change the file's identity.
    private static func updateOpenTabs(matching refreshed: ConnectorNode,
                                       in store: WorkspaceStore) {
        for doc in store.tabs.documents {
            guard doc.connectorNode?.id == refreshed.id else { continue }
            // Rename / move preserve fileID — only origin.displayPath
            // (and connectorID, which is invariant) changes.
            let newOrigin: EditorDocument.Origin
            switch doc.origin {
            case .local:
                newOrigin = .local
            case .portableMind(let cid, let fid, _):
                newOrigin = .portableMind(
                    connectorID: cid,
                    fileID: fid,
                    displayPath: refreshed.path)
            }
            doc.updateAfterRenameOrMove(
                newOrigin: newOrigin,
                newConnectorNode: refreshed)
        }
    }

    // MARK: - Helpers

    /// Translate a freshly-created `ConnectorNode` into the corresponding
    /// `(EditorDocument.Origin, URL?)` pair. PM connectors yield
    /// `.portableMind(...)` with no URL; Local yields `.local` with a
    /// file URL. Unrecognized connector kinds fall back to `.local`
    /// with a best-effort URL — matches D18's "Local is the default"
    /// posture.
    private static func mapNodeToOrigin(
        _ node: ConnectorNode,
        parentConnector: any Connector
    ) -> (EditorDocument.Origin, URL?) {
        if parentConnector is PortableMindConnector,
           let fileID = parsePMFileID(node.id) {
            let origin = EditorDocument.Origin.portableMind(
                connectorID: parentConnector.id,
                fileID: fileID,
                displayPath: node.path)
            return (origin, nil)
        }
        return (.local, URL(fileURLWithPath: node.path))
    }

    /// Parse the numeric LlmFile id out of a PortableMind `ConnectorNode.id`
    /// (format `"<connectorID>:file:<numericID>"`). Mirrors the parser
    /// in PortableMindConnector but lives here to keep PMFileOperations
    /// independent of the connector's internals — caller passes node id.
    private static func parsePMFileID(_ nodeID: String) -> Int? {
        let parts = nodeID.split(separator: ":")
        guard parts.count >= 3, parts[parts.count - 2] == "file",
              let fileID = Int(parts[parts.count - 1])
        else { return nil }
        return fileID
    }
}
