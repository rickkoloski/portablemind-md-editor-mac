import AppKit
import Combine
import Foundation

/// Per-tab state. Each open file in the workspace is one
/// `EditorDocument`. Owns the source buffer, the associated
/// `DocumentType`, and the external-edit watcher that reflects disk
/// changes into the buffer.
///
/// Named with the `Editor` prefix to avoid collision with swift-
/// markdown's `Markdown.Document` type, which the renderer uses for
/// AST traversal.
@MainActor
final class EditorDocument: ObservableObject, Identifiable {
    let id = UUID()

    @Published var url: URL?
    @Published var source: String
    @Published var externallyDeleted: Bool = false
    /// D9: an external command (CLI / URL scheme / future MCP) can
    /// request that the editor place the caret at a specific target
    /// after the document is shown. The EditorContainer's coordinator
    /// consumes this and clears it back to `nil` on apply.
    @Published var pendingFocusTarget: EditorFocusTarget? = nil

    let documentType: any DocumentType

    private let watcher = ExternalEditWatcher()

    init(url: URL?, source: String, documentType: any DocumentType) {
        self.url = url
        self.source = source
        self.documentType = documentType

        watcher.onChange = { [weak self] newText in
            guard let self else { return }
            Task { @MainActor in
                self.externallyDeleted = false
                self.source = newText
            }
        }
        if let url { watcher.watch(url: url) }
    }

    deinit {
        watcher.stop()
    }

    /// The filename shown in the tab and the empty-state placeholder.
    var displayName: String {
        url?.lastPathComponent ?? "Untitled"
    }
}
