// D18 phase 3 — view-model for one connector's tree pane.
//
// Unifies sync (LocalConnector) and async (PortableMindConnector)
// children loading behind a single API. The view checks
// `isExpanded(path)`, `childrenIfLoaded(at:)`, `isLoading(path)`, and
// `errorMessage(at:)` for each row; the view-model handles the async
// dance internally.

import Foundation
import SwiftUI

@MainActor
final class ConnectorTreeViewModel: ObservableObject {
    let connector: any Connector

    /// Paths whose disclosure is open. The connector's root path is
    /// inserted at construction so the root expands by default
    /// (Finder convention).
    @Published private(set) var expanded: Set<String>

    /// Async-loaded children, keyed by parent path. Only populated for
    /// connectors that return nil from `childrenSync(of:)`.
    @Published private(set) var asyncChildren: [String: [ConnectorNode]] = [:]

    /// Paths currently being loaded (network IO in flight). UI shows a
    /// spinner next to the row's disclosure chevron.
    @Published private(set) var loadingPaths: Set<String> = []

    /// Last error encountered loading a path's children. Cleared on
    /// successful re-load.
    @Published private(set) var errors: [String: String] = [:]

    /// Authenticated user's tenant id, for the cross-tenant badge
    /// predicate. Lazy-fetched at init for connectors that supply
    /// it (PortableMind). nil for connectors with no tenant model
    /// (Local).
    @Published private(set) var currentUserTenantID: Int?

    init(connector: any Connector) {
        self.connector = connector
        self.expanded = [connector.rootNode.path]
        // For async connectors, kick off the root load eagerly so the
        // root row's spinner animates from the moment the sidebar
        // mounts (rather than after the user clicks expand).
        if connector.childrenSync(of: connector.rootNode.path) == nil {
            Task { [weak self] in
                await self?.loadChildren(at: connector.rootNode.path)
            }
        }
        // Prime the cross-tenant badge predicate. PortableMind exposes
        // currentUserTenantID(); other connectors don't (default
        // protocol method below returns nil).
        if let pm = connector as? PortableMindConnector {
            Task { [weak self] in
                if let id = try? await pm.currentUserTenantID() {
                    await MainActor.run { self?.currentUserTenantID = id }
                }
            }
        }
    }

    /// Whether `node`'s tenant differs from the authenticated user's
    /// tenant. Drives the cross-tenant badge in the sidebar. Returns
    /// false if the node has no tenant attribution OR we haven't
    /// loaded the user's tenant yet.
    func isCrossTenant(_ node: ConnectorNode) -> Bool {
        guard let nodeTenant = node.tenant?.id,
              let userTenant = currentUserTenantID
        else { return false }
        return nodeTenant != userTenant
    }

    // MARK: - View queries

    func isExpanded(_ path: String) -> Bool {
        expanded.contains(path)
    }

    func isLoading(_ path: String) -> Bool {
        loadingPaths.contains(path)
    }

    func errorMessage(at path: String) -> String? {
        errors[path]
    }

    /// Children to render for `path`. Returns:
    /// - sync result for connectors with local IO (always available)
    /// - cached async result if we've loaded it
    /// - nil if a load is in flight or hasn't started
    func childrenIfLoaded(at path: String) -> [ConnectorNode]? {
        if let sync = connector.childrenSync(of: path) {
            return sync
        }
        return asyncChildren[path]
    }

    // MARK: - Mutations (UI + harness drive these)

    /// Toggle expansion of `path`. If the connector is async and
    /// children haven't been loaded yet, kicks off a load.
    func toggle(path: String) {
        if expanded.contains(path) {
            expanded.remove(path)
            return
        }
        expanded.insert(path)
        if connector.childrenSync(of: path) == nil
            && asyncChildren[path] == nil
            && !loadingPaths.contains(path)
        {
            Task { [weak self] in await self?.loadChildren(at: path) }
        }
    }

    /// Force-expand `path`. Idempotent; loads children if needed.
    /// Async — caller can `await` to know when load completes.
    func expand(path: String) async {
        if !expanded.contains(path) {
            expanded.insert(path)
        }
        if connector.childrenSync(of: path) == nil
            && asyncChildren[path] == nil
        {
            await loadChildren(at: path)
        }
    }

    /// Force-collapse `path`. Preserves any cached children so a
    /// subsequent expand renders instantly.
    func collapse(path: String) {
        expanded.remove(path)
    }

    // MARK: - Async load

    private func loadChildren(at path: String) async {
        loadingPaths.insert(path)
        errors.removeValue(forKey: path)
        do {
            let kids = try await connector.children(of: path)
            asyncChildren[path] = kids
        } catch {
            errors[path] = describe(error)
        }
        loadingPaths.remove(path)
    }

    private func describe(_ error: Error) -> String {
        if let cerr = error as? ConnectorError {
            switch cerr {
            case .unauthenticated:
                return "Not signed in — set token in Debug menu"
            case .network(let underlying):
                return "Network: \(underlying.localizedDescription)"
            case .server(let status, let message):
                return "Server \(status): \(message ?? "")"
            case .unsupported(let msg):
                return "Unsupported: \(msg)"
            // D19 — these are save-path errors; the children loader
            // shouldn't normally hit them, but exhaustiveness requires
            // a branch.
            case .storageQuotaExceeded(let msg):
                return "Storage quota exceeded: \(msg)"
            case .writeForbidden(let msg):
                return "Write forbidden: \(msg)"
            case .conflictDetected:
                return "Conflict: file changed remotely"
            }
        }
        return error.localizedDescription
    }
}
