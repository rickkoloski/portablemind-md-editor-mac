// D18 phase 3 — Connector backed by Harmoniq's REST API. Async-only:
// `childrenSync(of:)` returns nil; the UI handles network IO via the
// connector tree view-model's expand-on-demand pattern.
//
// Path semantics follow the Rails LlmDirectory `path` field
// convention: "/" (root), "/projects", "/projects/2024/docs", etc.
// `nil` is treated as root for `children(of:)`.
//
// The user's tenant_id (for cross-tenant badge logic) is fetched lazily
// on first need and cached for the connector's lifetime. D18 phase 3
// does not yet render badges; the cache primes during phase 4.

import Foundation

final class PortableMindConnector: Connector {
    private let api: PortableMindAPIClient
    /// Cache of the authenticated user's tenant_id. nil until first
    /// fetch. Phase 4 reads this for badge predicate.
    private var cachedUserTenantID: Int?

    init(api: PortableMindAPIClient = PortableMindAPIClient()) {
        self.api = api
    }

    // MARK: - Connector

    let id = "portablemind"
    let rootName = "PortableMind"
    let rootIconName = "icloud"

    var rootNode: ConnectorNode {
        ConnectorNode(
            id: "\(id):root",
            name: rootName,
            path: "",
            kind: .directory,
            fileCount: nil,
            tenant: nil,
            isSupported: true,
            connector: self
        )
    }

    func children(of path: String?) async throws -> [ConnectorNode] {
        // PM API uses "/" for root; nil and "" map to "/".
        let normalizedParent: String
        if let path, !path.isEmpty {
            normalizedParent = path
        } else {
            normalizedParent = "/"
        }

        // Two parallel calls: directories under this path, files in
        // this path. Combine into a single ConnectorNode list.
        async let dirs = api.listDirectories(parentPath: normalizedParent,
                                             crossTenant: true)
        async let files = api.listFiles(directoryPath: normalizedParent)

        let (dirDTOs, fileDTOs) = try await (dirs, files)

        let dirNodes = dirDTOs.map { dto in
            ConnectorNode(
                id: "\(id):dir:\(dto.id)",
                name: dto.name,
                path: dto.path,
                kind: .directory,
                fileCount: dto.file_count,
                tenant: tenantInfo(from: dto),
                isSupported: true,
                connector: self
            )
        }

        let fileNodes = fileDTOs.map { dto in
            ConnectorNode(
                id: "\(id):file:\(dto.id)",
                name: dto.title,
                path: dto.full_path ?? "\(normalizedParent)/\(dto.title)",
                kind: .file,
                fileCount: nil,
                tenant: tenantInfo(from: dto),
                isSupported: isSupportedFile(dto),
                connector: self
            )
        }

        // Directories first, alphabetic case-insensitive within each
        // group — match LocalConnector's ordering for consistency.
        let combined = dirNodes + fileNodes
        return combined.sorted { lhs, rhs in
            if (lhs.kind == .directory) != (rhs.kind == .directory) {
                return lhs.kind == .directory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                == .orderedAscending
        }
    }

    func childrenSync(of path: String?) -> [ConnectorNode]? { nil }

    func openFile(_ node: ConnectorNode) async throws -> (Data, ConnectorNode) {
        guard node.kind == .file else {
            throw ConnectorError.unsupported("openFile called on directory node")
        }
        let fileID = try Self.fileID(from: node, connectorID: id)
        // Two-step like fetchFileContent, but expose the meta's
        // updated_at so the refreshed node carries the freshness baseline
        // for D19 phase 4 conflict detection.
        let meta = try await api.fetchFileMeta(fileID: fileID)
        guard let urlString = meta.url, let url = URL(string: urlString) else {
            throw ConnectorError.server(
                status: 200, message: "llm_files/\(fileID): missing url")
        }
        let bytes = try await api.fetchSignedBlob(url: url)
        let updatedAt = meta.updated_at.flatMap(
            ISO8601DateFormatter.fractional.date(from:))
        let refreshed = ConnectorNode(
            id: node.id,
            name: node.name,
            path: node.path,
            kind: node.kind,
            fileCount: node.fileCount,
            tenant: node.tenant,
            isSupported: node.isSupported,
            lastSeenUpdatedAt: updatedAt ?? node.lastSeenUpdatedAt,
            connector: self
        )
        return (bytes, refreshed)
    }

    /// D19 phase 3 — PortableMind supports write on any `.file` node.
    /// Per-file permission denial surfaces as `ConnectorError.writeForbidden`
    /// from `saveFile`; the editor flips the tab back to read-only at
    /// that point. Future (D20+): respect a per-node `permissions`
    /// field if Harmoniq surfaces one in the read response.
    func canWrite(_ node: ConnectorNode) -> Bool {
        node.kind == .file
    }

    /// D19 phase 3 — write `bytes` to the PM file backing `node` via
    /// `PortableMindAPIClient.updateFile`. Multipart PATCH; the
    /// LlmFile.title is preserved (we pass it through as the multipart
    /// filename so the ActiveStorage blob keeps a sensible filename).
    /// Returns a refreshed ConnectorNode with the new
    /// `lastSeenUpdatedAt` so callers can pick it up for phase 4's
    /// conflict prompt.
    ///
    /// D19 phase 4 — when `force == false` and the node carries a
    /// `lastSeenUpdatedAt` baseline, GET the current meta first and
    /// compare. If the server's `updated_at` is newer, throw
    /// `.conflictDetected` so the menu handler can prompt the user
    /// (Q2 decision: server-wins warning). Graceful fallback: if the
    /// meta GET fails with a network-class error, fall through to the
    /// PATCH (last-writer-wins) — flaky network shouldn't block saves.
    /// Auth/server failures on the meta GET propagate normally.
    func saveFile(_ node: ConnectorNode,
                  bytes: Data,
                  force: Bool) async throws -> ConnectorNode {
        guard node.kind == .file else {
            throw ConnectorError.unsupported("saveFile called on directory node")
        }
        let fileID = try Self.fileID(from: node, connectorID: id)

        // Phase 4 conflict check.
        if !force, let lastSeen = node.lastSeenUpdatedAt {
            var serverUpdatedAt: Date? = nil
            do {
                let meta = try await api.fetchFileMeta(fileID: fileID)
                serverUpdatedAt = meta.updated_at.flatMap(
                    ISO8601DateFormatter.fractional.date(from:))
            } catch ConnectorError.network {
                // Graceful fallback — proceed with PATCH.
                serverUpdatedAt = nil
            }
            // Compare with millisecond tolerance — the server stores
            // sub-millisecond precision but we round-trip through
            // ISO8601 strings. A tolerance below the timestamp's
            // resolution wouldn't false-positive on identical writes.
            if let server = serverUpdatedAt,
               server.timeIntervalSince(lastSeen) > 0.001 {
                throw ConnectorError.conflictDetected(
                    serverUpdatedAt: server)
            }
        }

        let updated = try await api.updateFile(
            fileID: fileID,
            bytes: bytes,
            filename: node.name)
        // Build a refreshed node with the new server timestamp.
        let updatedAt = updated.updated_at.flatMap(
            ISO8601DateFormatter.fractional.date(from:))
        return ConnectorNode(
            id: node.id,
            name: node.name,
            path: node.path,
            kind: node.kind,
            fileCount: node.fileCount,
            tenant: node.tenant,
            isSupported: node.isSupported,
            lastSeenUpdatedAt: updatedAt ?? node.lastSeenUpdatedAt,
            connector: self
        )
    }

    /// Parse the numeric LlmFile id out of a `ConnectorNode.id` of the
    /// form `"portablemind:file:<id>"`. Static so both `openFile` and
    /// `saveFile` share the same parser.
    private static func fileID(from node: ConnectorNode,
                               connectorID: String) throws -> Int {
        let prefix = "\(connectorID):file:"
        guard node.id.hasPrefix(prefix),
              let fileID = Int(node.id.dropFirst(prefix.count))
        else {
            throw ConnectorError.unsupported(
                "couldn't parse PM file id from node id \(node.id)")
        }
        return fileID
    }

    // MARK: - D23 file management

    /// Build a `ConnectorNode` from a server FileDTO. The directory_path
    /// (or full_path) drives the displayed path; tenant + supported
    /// flags mirror what `children(of:)` produces. Used by create /
    /// rename / move to refresh the open tab's connectorNode after the
    /// server commits the change.
    private func node(from dto: FileDTO) -> ConnectorNode {
        let parentPath = dto.directory_path ?? "/"
        let path = dto.full_path
            ?? (parentPath.hasSuffix("/")
                ? "\(parentPath)\(dto.title)"
                : "\(parentPath)/\(dto.title)")
        return ConnectorNode(
            id: "\(id):file:\(dto.id)",
            name: dto.title,
            path: path,
            kind: .file,
            fileCount: nil,
            tenant: tenantInfo(from: dto),
            isSupported: isSupportedFile(dto),
            lastSeenUpdatedAt: dto.updated_at.flatMap(
                ISO8601DateFormatter.fractional.date(from:)),
            connector: self)
    }

    func createFile(in parent: ConnectorNode,
                    name: String,
                    bytes: Data) async throws -> ConnectorNode {
        guard parent.kind == .directory else {
            throw ConnectorError.unsupported(
                "createFile parent must be a directory")
        }
        let dto = try await api.createFile(
            directoryPath: parent.path,
            name: name,
            bytes: bytes)
        return node(from: dto)
    }

    func renameFile(_ node: ConnectorNode,
                    to newName: String) async throws -> ConnectorNode {
        guard node.kind == .file else {
            throw ConnectorError.unsupported(
                "renameFile called on directory node (file-only in v1)")
        }
        let fileID = try Self.fileID(from: node, connectorID: id)
        let dto = try await api.renameFile(fileID: fileID, newName: newName)
        return self.node(from: dto)
    }

    func moveFile(_ node: ConnectorNode,
                  to newParent: ConnectorNode) async throws -> ConnectorNode {
        guard node.kind == .file else {
            throw ConnectorError.unsupported(
                "moveFile called on directory node (file-only in v1)")
        }
        guard newParent.kind == .directory else {
            throw ConnectorError.unsupported(
                "moveFile target must be a directory")
        }
        // Q6 — cross-tenant moves not supported in v1. The tree picker
        // disallows it; this is the connector-level guard.
        if let src = node.tenant, let dst = newParent.tenant,
           src.id != dst.id {
            throw ConnectorError.unsupported(
                "cross-tenant moves not supported in v1")
        }
        let fileID = try Self.fileID(from: node, connectorID: id)
        let dto = try await api.moveFile(
            fileID: fileID, newDirectoryPath: newParent.path)
        return self.node(from: dto)
    }

    // MARK: - D23.1 destructive ops + directory create

    func deleteFile(_ node: ConnectorNode) async throws {
        guard node.kind == .file else {
            throw ConnectorError.unsupported(
                "deleteFile called on directory node")
        }
        let fileID = try Self.fileID(from: node, connectorID: id)
        try await api.deleteFile(fileID: fileID)
    }

    func createDirectory(in parent: ConnectorNode,
                         name: String) async throws -> ConnectorNode {
        guard parent.kind == .directory else {
            throw ConnectorError.unsupported(
                "createDirectory parent must be a directory")
        }
        let dto = try await api.createDirectory(
            parentPath: parent.path, name: name)
        return directoryNode(from: dto)
    }

    func deleteDirectory(_ node: ConnectorNode) async throws {
        guard node.kind == .directory else {
            throw ConnectorError.unsupported(
                "deleteDirectory called on file node")
        }
        let dirID = try Self.directoryID(from: node, connectorID: id)
        try await api.deleteDirectory(directoryID: dirID)
    }

    /// Build a `ConnectorNode` from a server DirectoryDTO. Mirrors the
    /// node construction in `children(of:)`.
    private func directoryNode(from dto: DirectoryDTO) -> ConnectorNode {
        return ConnectorNode(
            id: "\(id):dir:\(dto.id)",
            name: dto.name,
            path: dto.path,
            kind: .directory,
            fileCount: dto.file_count ?? 0,
            tenant: tenantInfo(from: dto),
            isSupported: true,
            connector: self)
    }

    /// Parse the numeric LlmDirectory id out of a `ConnectorNode.id` of
    /// the form `"<connectorID>:dir:<id>"`. Static so this and any
    /// future directory-mutation method share the parser.
    private static func directoryID(from node: ConnectorNode,
                                    connectorID: String) throws -> Int {
        let prefix = "\(connectorID):dir:"
        guard node.id.hasPrefix(prefix),
              let dirID = Int(node.id.dropFirst(prefix.count))
        else {
            throw ConnectorError.unsupported(
                "couldn't parse PM directory id from node id \(node.id)")
        }
        return dirID
    }

    // MARK: - Helpers

    private func tenantInfo(from dto: DirectoryDTO) -> TenantInfo? {
        guard let identifier = dto.tenant_enterprise_identifier,
              let name = dto.tenant_name else { return nil }
        return TenantInfo(
            id: dto.tenant_id,
            name: name,
            enterpriseIdentifier: identifier)
    }

    private func tenantInfo(from dto: FileDTO) -> TenantInfo? {
        guard let identifier = dto.tenant_enterprise_identifier,
              let name = dto.tenant_name else { return nil }
        return TenantInfo(
            id: dto.tenant_id,
            name: name,
            enterpriseIdentifier: identifier)
    }

    /// D18: `.md` only. Future: source from the document-type registry.
    private func isSupportedFile(_ dto: FileDTO) -> Bool {
        let name = dto.title.lowercased()
        return name.hasSuffix(".md") || name.hasSuffix(".markdown")
    }

    /// Phase 4 reads this for the cross-tenant badge predicate.
    /// Lazy-fetched and cached for the connector's lifetime.
    func currentUserTenantID() async throws -> Int {
        if let cached = cachedUserTenantID { return cached }
        let user = try await api.currentUser()
        cachedUserTenantID = user.tenant_id
        return user.tenant_id
    }
}
