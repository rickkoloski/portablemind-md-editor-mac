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

    func openFile(_ node: ConnectorNode) async throws -> Data {
        guard node.kind == .file else {
            throw ConnectorError.unsupported("openFile called on directory node")
        }
        let fileID = try Self.fileID(from: node, connectorID: id)
        return try await api.fetchFileContent(fileID: fileID)
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
    /// `force` is reserved for phase 4 (skip the GET-before-PATCH
    /// optimistic check). Phase 3 ignores it; phase 4 wires it up.
    func saveFile(_ node: ConnectorNode,
                  bytes: Data,
                  force: Bool) async throws -> ConnectorNode {
        guard node.kind == .file else {
            throw ConnectorError.unsupported("saveFile called on directory node")
        }
        let fileID = try Self.fileID(from: node, connectorID: id)
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
