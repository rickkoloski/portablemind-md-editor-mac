import Foundation

/// Change the workspace root to a folder.
///
/// URL form: `md-editor://open-folder?path=<url-encoded-absolute-path>`
///
/// The app persists the new root via security-scoped bookmark so the
/// workspace reopens on next launch.
@MainActor
enum OpenFolderCommand: ExternalCommand {
    static let identifier = ExternalCommandIdentifier.openFolder

    static func execute(params: [String: String], in workspace: WorkspaceStore) {
        guard let rawPath = params["path"],
              let decoded = rawPath.removingPercentEncoding
        else {
            NSLog("OpenFolderCommand: missing `path` parameter")
            return
        }
        let url = URL(fileURLWithPath: decoded)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            NSLog("OpenFolderCommand: path is not a directory: \(url.path)")
            return
        }
        // URL-scheme-launched file access typically does not require
        // a startAccessingSecurityScopedResource call; the OS grants
        // the equivalent via the URL event. We still persist a
        // security-scoped bookmark (inside WorkspaceStore.setRoot →
        // SecurityScopedBookmarkStore.save) so future launches can
        // resolve access without prompting.
        workspace.setRoot(url: url)
    }
}
