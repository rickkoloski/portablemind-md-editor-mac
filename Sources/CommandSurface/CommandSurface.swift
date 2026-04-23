import Foundation

/// Single registry of external commands — CLI / URL scheme / future
/// MCP adapter all route through here per engineering-standards §2.4.
/// D6 introduces the first two commands (open file, open folder);
/// later deliverables extend the registry.
///
/// Stubbed for Batch 3 so WorkspaceStore can call drainPending;
/// Batch 4 fills in the real registry + dispatch.
enum CommandSurface {
    private static var pending: [(identifier: String, params: [String: String])] = []
    private static var ready = false

    /// Pre-workspace URL events arrive before `WorkspaceStore
    /// .restoreFromBookmarks()` completes. Buffer them; drain once
    /// the workspace signals ready.
    static func enqueue(identifier: String, params: [String: String]) {
        pending.append((identifier, params))
    }

    static func drainPending(in workspace: WorkspaceStore) {
        ready = true
        let toRun = pending
        pending.removeAll()
        for event in toRun {
            dispatch(identifier: event.identifier, params: event.params, in: workspace)
        }
    }

    static func dispatch(identifier: String,
                         params: [String: String],
                         in workspace: WorkspaceStore) {
        // Batch 4 will replace this with a proper registry lookup.
        NSLog("CommandSurface: dispatch stub — identifier=\(identifier) params=\(params)")
    }
}
