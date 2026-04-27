// D18 phase 1 — Connector backed by the local filesystem. Wraps the
// existing FolderTreeLoader-style walk; semantics are unchanged from
// D6's behavior (lazy directory walk, dotfile + well-known-clutter
// filter, dirs-before-files alphabetic sort).
//
// Supported file types: `.md` only for D18. Other names appear in the
// tree as nodes with `isSupported = false` so the sidebar can render
// them disabled per the D18 spec Q1 decision.

import Foundation

/// Filter rules — anything starting with `.` is hidden, plus a small
/// allowlist of well-known directories we don't want cluttering the
/// sidebar. User-visible "show hidden" toggle is out of scope for D18;
/// inherited from D6.
enum LocalConnectorFilter {
    static let excludedNames: Set<String> = [
        ".git",
        ".build",
        ".build-xcode",
        ".swiftpm",
        ".DS_Store",
        "DerivedData",
        "node_modules",
        "Pods",
    ]

    static func shouldShow(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        if excludedNames.contains(name) { return false }
        return true
    }
}

final class LocalConnector: Connector {
    /// Workspace root URL. Immutable for the connector's lifetime —
    /// when the user picks a different workspace folder,
    /// `WorkspaceStore` constructs a fresh `LocalConnector` rather than
    /// mutating this one. Keeps the connector trivially `Sendable`.
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    // MARK: - Connector

    let id = "local"
    let rootIconName = "folder"
    var rootName: String { rootURL.lastPathComponent }

    var rootNode: ConnectorNode {
        ConnectorNode(
            id: "\(id):\(rootURL.path)",
            name: rootURL.lastPathComponent,
            path: rootURL.path,
            kind: .directory,
            fileCount: nil,
            tenant: nil,
            isSupported: true,
            connector: self
        )
    }

    func children(of path: String?) async throws -> [ConnectorNode] {
        // Local IO is fast; the async surface delegates to the sync
        // implementation. Future: if directory walks become slow on
        // huge trees, hop off the main thread here.
        return childrenSync(of: path) ?? []
    }

    func childrenSync(of path: String?) -> [ConnectorNode]? {
        let url: URL = {
            if let path, !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return rootURL
        }()
        return walkChildren(of: url)
    }

    func openFile(_ node: ConnectorNode) async throws -> Data {
        let url = URL(fileURLWithPath: node.path)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ConnectorError.network(error)
        }
    }

    /// Local files are always writable from the connector's POV; OS-
    /// level permission denial would surface as a `ConnectorError.network`
    /// from the write call itself.
    func canWrite(_ node: ConnectorNode) -> Bool {
        node.kind == .file
    }

    /// Atomic UTF-8 write — mirrors D14 `EditorDocument.writeAndRewatch`.
    /// Local has no remote-mtime concept, so the conflict-detection
    /// `force` flag is ignored (no GET-before-PATCH equivalent on disk;
    /// D14 didn't try). Returns the same node back; `lastSeenUpdatedAt`
    /// stays nil for Local because there's no canonical remote time
    /// to track.
    ///
    /// NOTE on the watcher: D14's `EditorDocument.writeAndRewatch` stops
    /// the watcher around the write to suppress the file-event echo.
    /// That guard belongs at the EditorDocument layer (it owns the
    /// watcher), not here. The connector just writes; the caller wraps.
    func saveFile(_ node: ConnectorNode,
                  bytes: Data,
                  force: Bool) async throws -> ConnectorNode {
        guard node.kind == .file else {
            throw ConnectorError.unsupported(
                "saveFile called on directory node")
        }
        let url = URL(fileURLWithPath: node.path)
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw ConnectorError.network(error)
        }
        return node
    }

    // MARK: - Walk

    private func walkChildren(of url: URL) -> [ConnectorNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let nodes: [ConnectorNode] = contents
            .filter(LocalConnectorFilter.shouldShow)
            .compactMap { childURL -> (URL, Bool)? in
                let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey])
                    .isDirectory) ?? false
                return (childURL, isDir)
            }
            .map { (childURL, isDir) in
                ConnectorNode(
                    id: "\(id):\(childURL.path)",
                    name: childURL.lastPathComponent,
                    path: childURL.path,
                    kind: isDir ? .directory : .file,
                    fileCount: nil,
                    tenant: nil,
                    isSupported: isDir || isSupportedFile(childURL),
                    connector: self
                )
            }

        return nodes.sorted { lhs, rhs in
            // Directories first; alphabetic within each group, case-
            // insensitive.
            if (lhs.kind == .directory) != (rhs.kind == .directory) {
                return lhs.kind == .directory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Whether the editor knows how to open this file. D18: `.md` only.
    /// Future: source from the document-type registry (D2's abstraction).
    private func isSupportedFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "md"
    }

}
