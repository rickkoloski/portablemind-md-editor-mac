import Foundation

/// Open a file in a tab.
///
/// URL form: `md-editor://open?path=<url-encoded-absolute-path>[&tab=new|existing][&line=N[&column=M]]`
///
/// `tab=existing` (default): focus the file's tab if already open;
/// otherwise open a new tab.
/// `tab=new`: always open a new tab, even if the file is already open.
///
/// `line` (D9, 1-based): after opening or focusing, place the caret at
/// the start of the given line and scroll to make it visible. Line
/// beyond EOF clamps to the last line.
/// `column` (D9, 1-based, optional): place the caret at the given
/// column on the target line. Column beyond end-of-line clamps.
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
        let doc = workspace.tabs.open(fileURL: url, forceNewTab: forceNewTab)

        // D11: view-state params (e.g. line_numbers=on) can ride along
        // on the open command. Apply them through the same applicator
        // that SetViewCommand uses so semantics are identical.
        ViewStateApplier.apply(params: params)

        if let doc, let lineStr = params["line"], let line = Int(lineStr) {
            let column = params["column"].flatMap(Int.init) ?? 1
            doc.pendingFocusTarget = .caret(line: line, column: column)
        }
    }
}
