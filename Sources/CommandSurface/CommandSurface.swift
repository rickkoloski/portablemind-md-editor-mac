import Foundation

/// The one and only place where external commands (CLI, URL scheme,
/// future MCP adapter) resolve to implementations. Per engineering-
/// standards §2.4 — any external-entry-point handler lives here; no
/// scattered switch statements in scene hooks or toolbar actions.
///
/// Pending-event queue: URL-scheme events can arrive before
/// `WorkspaceStore.restoreFromBookmarks` completes on app launch.
/// Such events are enqueued and drained once the workspace signals
/// ready.
@MainActor
enum CommandSurface {
    // MARK: - Registry

    private static let registry: [ExternalCommandIdentifier: any ExternalCommand.Type] = [
        OpenFileCommand.identifier: OpenFileCommand.self,
        OpenFolderCommand.identifier: OpenFolderCommand.self,
    ]

    // MARK: - Pending-event queue

    private static var pending: [(identifier: String, params: [String: String])] = []

    /// Called by `URLSchemeHandler` when an event arrives before the
    /// workspace is ready.
    static func enqueue(identifier: String, params: [String: String]) {
        pending.append((identifier, params))
    }

    /// Called by `WorkspaceStore.restoreFromBookmarks` once the
    /// workspace has restored from its persistence layer.
    static func drainPending(in workspace: WorkspaceStore) {
        let toRun = pending
        pending.removeAll()
        for event in toRun {
            dispatch(identifier: event.identifier, params: event.params, in: workspace)
        }
    }

    // MARK: - Dispatch

    /// Resolve `identifier` to a registered command and execute it.
    /// Unknown identifiers log and no-op rather than crash — CLI
    /// invocations from shell can typo or use an older app version.
    static func dispatch(identifier: String,
                         params: [String: String],
                         in workspace: WorkspaceStore) {
        guard let typed = ExternalCommandIdentifier(rawValue: identifier) else {
            NSLog("CommandSurface: unknown command identifier '\(identifier)'")
            return
        }
        guard let command = registry[typed] else {
            NSLog("CommandSurface: no handler registered for identifier '\(identifier)'")
            return
        }
        command.execute(params: params, in: workspace)
    }
}
