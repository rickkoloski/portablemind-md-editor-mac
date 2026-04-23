import Foundation

/// Entry point for `md-editor://…` URL events. Parses, looks up the
/// identifier, and hands off to `CommandSurface`. Batch 4 wires the
/// actual `CommandSurface` registry; Batch 3 keeps this as a stub so
/// the scene's `.onOpenURL` compiles.
@MainActor
enum URLSchemeHandler {
    static func handle(_ url: URL, workspace: WorkspaceStore) {
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
        if workspace.isReady {
            CommandSurface.dispatch(identifier: identifier, params: params, in: workspace)
        } else {
            CommandSurface.enqueue(identifier: identifier, params: params)
        }
    }
}
