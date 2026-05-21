import Foundation

/// Entry point for SwiftUI `.onOpenURL` events. Handles two shapes:
///
/// - **`md-editor://…` URL scheme** (CLI, future MCP) — parsed and
///   dispatched through `CommandSurface` by identifier (= URL host).
/// - **`file://…` URLs from LaunchServices** (Finder "Open With",
///   double-click on a registered file type per `CFBundleDocumentTypes`)
///   — routed to `OpenFileCommand` so the file opens as a tab.
///
/// In both cases, events that arrive before `WorkspaceStore.isReady`
/// are queued via `CommandSurface.enqueue` and drained once
/// `restoreFromBookmarks` completes.
@MainActor
enum URLSchemeHandler {
    static func handle(_ url: URL, workspace: WorkspaceStore) {
        // Finder "Open With" / double-click: macOS delivers the file
        // through LaunchServices as a file:// URL. Route it to
        // OpenFileCommand with `path` so the file gets opened as a tab
        // (and benefits from the existing not-yet-ready queue).
        if url.isFileURL {
            dispatchOrEnqueue(
                identifier: ExternalCommandIdentifier.openFile.rawValue,
                params: ["path": url.path],
                in: workspace)
            return
        }

        guard url.scheme == "md-editor", let identifier = url.host else {
            NSLog("URLSchemeHandler: unrecognized URL \(url)")
            return
        }
        var params: [String: String] = [:]
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                if let v = item.value { params[item.name] = v }
            }
        }
        dispatchOrEnqueue(identifier: identifier, params: params, in: workspace)
    }

    private static func dispatchOrEnqueue(identifier: String,
                                          params: [String: String],
                                          in workspace: WorkspaceStore) {
        if workspace.isReady {
            CommandSurface.dispatch(identifier: identifier, params: params, in: workspace)
        } else {
            CommandSurface.enqueue(identifier: identifier, params: params)
        }
    }
}
