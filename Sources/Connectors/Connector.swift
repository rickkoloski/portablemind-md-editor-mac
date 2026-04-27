// D18 — Connector protocol: storage backend abstraction for the
// workspace pane. Realizes the "File-system abstraction" from
// docs/stack-alternatives.md §3 (one of the nine cross-OS abstractions
// the editor commits to). Concrete implementations live alongside this
// file in Sources/Connectors/.
//
// Design notes:
//
// 1. Async by default. Even local IO goes through `async throws` so the
//    sidebar's call sites are uniform whether the backing connector is
//    local disk, a network API, or an MCP-mediated source.
//
// 2. Path semantics are connector-defined. The protocol takes opaque
//    `String` paths; meanings are documented per implementation.
//    LocalConnector uses URL.path strings rooted at the workspace
//    folder. PortableMindConnector (D18 phase 3) follows the
//    LlmDirectory `path` field convention (`/`, `/projects`, …).
//
// 3. Hash/equality on ConnectorNode is by `id` alone — caller is
//    responsible for ensuring `id` is globally unique within a
//    connector (typically a connector-prefixed identifier such as
//    "local:<URL>" or "pm:<numeric-id>").
//
// 4. `children` on ConnectorNode is a *synchronous* convenience for
//    SwiftUI's `OutlineGroup(_:children:)`, which requires a KeyPath
//    target. Connectors that can vend children synchronously
//    (LocalConnector) implement `childrenSync(of:)`. Connectors that
//    require async loading (PortableMindConnector) return nil from
//    `childrenSync` and the UI uses a different pattern (DisclosureGroup
//    with explicit Task.init on expand) — that wiring lands in phase 3.

import Foundation

/// A storage backend the workspace pane can show as a tree root.
///
/// Implementations are reference types so the per-`ConnectorNode` field
/// can be a non-owning pointer back to the connector for lazy child
/// loading.
protocol Connector: AnyObject, Sendable {
    /// Stable identifier — used as a prefix in `ConnectorNode.id`s to
    /// keep nodes from different connectors distinct. e.g. "local",
    /// "pm.<connection-id>".
    var id: String { get }

    /// Display label for the connector's root row. e.g. "Local",
    /// "PortableMind".
    var rootName: String { get }

    /// SF Symbol name for the root row icon. e.g. "folder",
    /// "icloud", "network".
    var rootIconName: String { get }

    /// Synthetic root node for the connector — the row the sidebar
    /// shows at the top of this connector's section. Its `path` is
    /// the value `children(of:)` resolves as "the root of this
    /// connector". Kind is always `.directory`.
    var rootNode: ConnectorNode { get }

    /// Children of `path`. `nil` means root.
    func children(of path: String?) async throws -> [ConnectorNode]

    /// Synchronous child accessor for connectors with local IO.
    /// Default: nil — async-only connector.
    func childrenSync(of path: String?) -> [ConnectorNode]?

    /// Read file content for `node`. D18 calls this only for nodes
    /// where `kind == .file && isSupported == true`. Connectors may
    /// throw `ConnectorError.unsupported` if they can't satisfy the
    /// read. The full node is passed (not just the path) so connectors
    /// can use any field they need — PortableMindConnector parses its
    /// numeric `LlmFile.id` out of `node.id`, while LocalConnector
    /// reads `node.path` as a URL.
    func openFile(_ node: ConnectorNode) async throws -> Data

    /// Whether this connector supports writing back to `node`. Used
    /// by the editor to decide whether a tab should be editable. The
    /// answer can change over the connector's lifetime (capability
    /// granted, network online/offline). Synchronous so the UI can
    /// ask cheaply on every render. Default: false.
    func canWrite(_ node: ConnectorNode) -> Bool

    /// Persist `bytes` as the new content of `node`. Throws on error.
    /// Returns the resulting `ConnectorNode` so callers can pick up
    /// any server-assigned values that changed (a fresh signed URL
    /// on PM; an updated mtime on Local; a refreshed
    /// `lastSeenUpdatedAt`). Default: throws `.unsupported`.
    ///
    /// `force == true` (D19 phase 4) skips the optimistic conflict
    /// check; the caller has explicitly agreed to overwrite a newer
    /// server version.
    func saveFile(_ node: ConnectorNode,
                  bytes: Data,
                  force: Bool) async throws -> ConnectorNode
}

extension Connector {
    func childrenSync(of path: String?) -> [ConnectorNode]? { nil }

    func canWrite(_ node: ConnectorNode) -> Bool { false }

    func saveFile(_ node: ConnectorNode,
                  bytes: Data,
                  force: Bool) async throws -> ConnectorNode {
        throw ConnectorError.unsupported(
            "saveFile not implemented by \(type(of: self))")
    }
}

/// Position in a connector's tree. Value type; carries a back-pointer
/// to its connector so SwiftUI can resolve children synchronously
/// where the connector supports it.
struct ConnectorNode: Identifiable, Hashable {
    /// Globally unique identity (caller-supplied; typically prefixed
    /// with the connector's `id` to disambiguate across connectors).
    let id: String
    let name: String
    let path: String
    let kind: Kind
    /// File count for directories, when the connector knows it.
    /// Renders as a caption next to the folder name. nil → not shown.
    let fileCount: Int?
    /// Tenant attribution for cross-tenant share badges (PortableMind).
    /// nil for local files.
    let tenant: TenantInfo?
    /// Whether the editor can open this file. `.directory` is always
    /// supported; for `.file` this is `true` iff the file extension is
    /// in the supported set (D18: `.md` only).
    let isSupported: Bool
    /// D19: server-side `updated_at` as last seen by this client. The
    /// connector populates this when it constructs the node from a
    /// server response (PortableMind); nil for connectors with no
    /// concept of remote mtime (Local). The save path uses this to
    /// detect concurrent edits.
    let lastSeenUpdatedAt: Date?
    /// Back-pointer to the owning connector so `children` can resolve
    /// synchronously where supported. Connectors are reference types;
    /// nodes never outlive their connector.
    let connector: any Connector

    init(id: String,
         name: String,
         path: String,
         kind: Kind,
         fileCount: Int? = nil,
         tenant: TenantInfo? = nil,
         isSupported: Bool = true,
         lastSeenUpdatedAt: Date? = nil,
         connector: any Connector) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.fileCount = fileCount
        self.tenant = tenant
        self.isSupported = isSupported
        self.lastSeenUpdatedAt = lastSeenUpdatedAt
        self.connector = connector
    }

    enum Kind: Hashable { case directory, file }

    /// Synchronous children accessor — used as the OutlineGroup KeyPath
    /// target. Returns:
    ///   - nil for non-directories (leaf row, no disclosure triangle)
    ///   - nil if the connector requires async loading
    ///   - the children array if the connector vends them synchronously
    var children: [ConnectorNode]? {
        guard kind == .directory else { return nil }
        return connector.childrenSync(of: path)
    }

    // MARK: Hashable / Equatable — by id only.
    static func == (lhs: ConnectorNode, rhs: ConnectorNode) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Cross-tenant attribution surfaced on PortableMind nodes.
struct TenantInfo: Hashable, Sendable {
    let id: Int
    /// Human-readable display name, e.g. "Istonish Prod Support".
    /// Used in tooltips.
    let name: String
    /// Short identifier used to derive badge initials, e.g. "RC", "E".
    let enterpriseIdentifier: String
}

/// Errors a connector can throw. Carry enough information for the
/// sidebar to render an inline error row (no NSError, no stringly-typed
/// status).
enum ConnectorError: Error {
    /// Operation isn't supported for this kind of path or this kind of
    /// connector. e.g. opening a directory, reading a non-`.md` file.
    case unsupported(String)
    /// No valid auth — credentials missing or expired.
    case unauthenticated
    /// Network-level failure (DNS, transport, decode).
    case network(Error)
    /// Server returned a non-2xx status.
    case server(status: Int, message: String?)
    /// D19: the user's tenant is over storage quota — distinct from
    /// generic server errors so the UI can surface a useful message
    /// (Harmoniq returns 402 with `error_code:
    /// DOCUMENT_STORAGE_LIMIT_EXCEEDED`).
    case storageQuotaExceeded(String)
    /// D19: explicit write-permission failure on save (401/403 from
    /// PATCH). Distinct from `.unauthenticated` so we can keep
    /// read-only browsing alive while save is denied.
    case writeForbidden(String)
    /// D19: the server's `updated_at` is newer than what the client
    /// last saw. Caller (the menu handler) catches this and prompts
    /// the user to overwrite or cancel (Q2 decision).
    case conflictDetected(serverUpdatedAt: Date)
}
