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

    /// D18 phase 5 — read-only tabs (PortableMind file open) cannot
    /// save and the editor disables typing. Save-back lands as a
    /// future deliverable after D19.
    let isReadOnly: Bool

    /// Where this document came from. `.local` for filesystem-backed
    /// tabs (the D6 path); `.portableMind(...)` for tabs opened via
    /// the connector.
    let origin: Origin

    enum Origin {
        case local
        case portableMind(connectorID: String, fileID: Int, displayPath: String)
    }

    let documentType: any DocumentType

    private let watcher = ExternalEditWatcher()

    init(url: URL?,
         source: String,
         documentType: any DocumentType,
         isReadOnly: Bool = false,
         origin: Origin = .local) {
        self.url = url
        self.source = source
        self.documentType = documentType
        self.isReadOnly = isReadOnly
        self.origin = origin

        watcher.onChange = { [weak self] newText in
            guard let self else { return }
            Task { @MainActor in
                self.externallyDeleted = false
                self.source = newText
            }
        }
        // PM read-only tabs have no local file to watch.
        if !isReadOnly, let url { watcher.watch(url: url) }
    }

    deinit {
        watcher.stop()
    }

    /// The filename shown in the tab and the empty-state placeholder.
    /// PM read-only tabs derive the name from the origin's display
    /// path since they have no `url`.
    var displayName: String {
        if let url { return url.lastPathComponent }
        switch origin {
        case .local:
            return "Untitled"
        case .portableMind(_, _, let displayPath):
            return (displayPath as NSString).lastPathComponent
        }
    }

    // MARK: - D14 Save / Save As

    enum SaveError: LocalizedError {
        case noURL
        case readOnly
        case writeFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .noURL:
                return "Document has no file location yet — use Save As…"
            case .readOnly:
                return "This document is read-only (PortableMind, D18). Save-back lands in a future deliverable."
            case .writeFailed(let url, let underlying):
                return "Couldn't save \(url.lastPathComponent): \(underlying.localizedDescription)"
            }
        }
    }

    /// Write the current `source` buffer to `url` as UTF-8. Pauses the
    /// external-edit watcher around the write so our own change doesn't
    /// echo back through `onChange` and overwrite a fresh user edit.
    /// Throws `.noURL` if the document is untitled — caller should
    /// fall back to `saveAs(to:)`. Throws `.readOnly` on PM tabs.
    func save() throws {
        if isReadOnly { throw SaveError.readOnly }
        guard let url else {
            throw SaveError.noURL
        }
        try writeAndRewatch(url: url)
    }

    /// Set a new URL for the document and write `source` there. Used
    /// by Save As and by Save on an untitled document.
    func saveAs(to newURL: URL) throws {
        if isReadOnly { throw SaveError.readOnly }
        try writeAndRewatch(url: newURL)
        // Update url after a successful write so a failed save doesn't
        // leave the document mis-pointed at a non-existent file.
        self.url = newURL
    }

    private func writeAndRewatch(url: URL) throws {
        watcher.stop()
        defer { watcher.watch(url: url) }
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw SaveError.writeFailed(url, error)
        }
    }
}
