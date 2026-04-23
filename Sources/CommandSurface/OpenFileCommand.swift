import Foundation

/// Open a file in a tab.
///
/// URL form: `md-editor://open?path=<url-encoded-absolute-path>[&tab=new|existing]`
///
/// `tab=existing` (default): focus the file's tab if already open;
/// otherwise open a new tab.
/// `tab=new`: always open a new tab, even if the file is already open.
@MainActor
enum OpenFileCommand: ExternalCommand {
    static let identifier = ExternalCommandIdentifier.openFile

    static func execute(params: [String: String], in workspace: WorkspaceStore) {
        guard let rawPath = params["path"],
              let decoded = rawPath.removingPercentEncoding
        else {
            NSLog("OpenFileCommand: missing `path` parameter")
            return
        }
        let url = URL(fileURLWithPath: decoded)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("OpenFileCommand: file does not exist at \(url.path)")
            return
        }
        let forceNewTab = (params["tab"] ?? "existing") == "new"
        _ = workspace.tabs.open(fileURL: url, forceNewTab: forceNewTab)
    }
}
