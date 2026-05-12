import Foundation

/// D30 — release a session's interest in a tab (or all tabs).
///
/// URL form: `md-editor://release?session=<id>&path=<url-encoded-absolute-path>`
///       or: `md-editor://release?session=<id>&all=true`
///
/// `session` (required): opaque session identifier whose interest is
/// being released.
/// `path` (required when `all` is absent): single file whose tab's
/// interest set should have `session` removed.
/// `all=true` (alternative to `path`): remove `session` from every
/// open tab's interest set.
///
/// Phase 2: parses + dispatches to `WorkspaceStore.releaseInterest`
/// (stub). Phase 3 wires the real mutation.
@MainActor
enum ReleaseSessionInterestCommand: ExternalCommand {
    static let identifier = ExternalCommandIdentifier.releaseSessionInterest

    static func execute(params: [String: String], in workspace: WorkspaceStore) {
        guard let sessionID = params["session"], !sessionID.isEmpty else {
            NSLog("ReleaseSessionInterestCommand: missing or empty `session` parameter")
            return
        }

        let isAll = (params["all"] ?? "").lowercased() == "true"
        if isAll {
            workspace.releaseInterest(sessionID: sessionID, scope: .all)
            return
        }

        guard let rawPath = params["path"],
              let decoded = rawPath.removingPercentEncoding
        else {
            NSLog("ReleaseSessionInterestCommand: missing `path` (and `all` is not true)")
            return
        }
        let url = URL(fileURLWithPath: decoded)
        workspace.releaseInterest(sessionID: sessionID, scope: .file(url))
    }
}
