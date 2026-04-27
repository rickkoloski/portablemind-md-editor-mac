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

    /// D18 phase 5 → D19 phase 3: read-only state.
    /// - Always false for `.local` origin.
    /// - For `.portableMind(...)`: starts as `!connector.canWrite(node)`
    ///   at open time. Save errors that imply permanent denial (write
    ///   forbidden) flip this to true.
    /// Reactive so EditorContainer can update `textView.isEditable`.
    @Published private(set) var isReadOnly: Bool

    /// D19 phase 3: in-flight save indicator. UI shows a small spinner
    /// next to the tab title. While true, ⌘S is a no-op (debounced —
    /// not queued). Optimistic: typing remains responsive.
    @Published private(set) var isSaving: Bool = false

    /// D19 phase 3: source-at-last-successful-save baseline. Drives the
    /// `dirty` predicate (source != lastSavedSource).
    @Published private(set) var lastSavedSource: String

    /// Where this document came from. `.local` for filesystem-backed
    /// tabs (the D6 path); `.portableMind(...)` for tabs opened via
    /// the connector.
    let origin: Origin

    enum Origin {
        case local
        case portableMind(connectorID: String, fileID: Int, displayPath: String)
    }

    /// D19 phase 3: the ConnectorNode the tab was opened from. Carries
    /// the connector reference, the file's `id` (for connector lookup)
    /// and `lastSeenUpdatedAt` (for phase 4's conflict detection).
    /// `nil` for `.local` origin (which uses the existing url path).
    /// Refreshed after every successful PM save so subsequent saves
    /// see the new server timestamp.
    private(set) var connectorNode: ConnectorNode?

    let documentType: any DocumentType

    private let watcher = ExternalEditWatcher()

    init(url: URL?,
         source: String,
         documentType: any DocumentType,
         isReadOnly: Bool = false,
         origin: Origin = .local,
         connectorNode: ConnectorNode? = nil) {
        self.url = url
        self.source = source
        self.lastSavedSource = source
        self.documentType = documentType
        self.isReadOnly = isReadOnly
        self.origin = origin
        self.connectorNode = connectorNode

        watcher.onChange = { [weak self] newText in
            guard let self else { return }
            Task { @MainActor in
                self.externallyDeleted = false
                self.source = newText
                self.lastSavedSource = newText
            }
        }
        // PM tabs have no local file to watch (read or write — saves
        // go through the connector, not the filesystem).
        let isPortableMind: Bool = {
            if case .portableMind = origin { return true }
            return false
        }()
        if !isPortableMind, let url { watcher.watch(url: url) }
    }

    deinit {
        watcher.stop()
    }

    /// D19 phase 3: source has unsaved edits relative to the last
    /// successful save. Local saves update `lastSavedSource` after
    /// `writeAndRewatch`; PM saves update it after `connector.saveFile`.
    var dirty: Bool { source != lastSavedSource }

    /// The filename shown in the tab and the empty-state placeholder.
    /// PM tabs derive the name from the origin's display path since
    /// they have no `url`.
    var displayName: String {
        if let url { return url.lastPathComponent }
        switch origin {
        case .local:
            return "Untitled"
        case .portableMind(_, _, let displayPath):
            return (displayPath as NSString).lastPathComponent
        }
    }

    // MARK: - D14 / D19 Save / Save As

    enum SaveError: LocalizedError {
        case noURL
        case readOnly
        case writeFailed(URL, Error)
        case writeForbidden(String)
        case storageQuotaExceeded(String)
        case networkSaveFailed(Error)
        case unsupportedSaveAs

        var errorDescription: String? {
            switch self {
            case .noURL:
                return "Document has no file location yet — use Save As…"
            case .readOnly:
                return "This document is read-only."
            case .writeFailed(let url, let underlying):
                return "Couldn't save \(url.lastPathComponent): \(underlying.localizedDescription)"
            case .writeForbidden(let body):
                return "Write denied by PortableMind: \(body)"
            case .storageQuotaExceeded(let body):
                return "PortableMind storage quota exceeded: \(body)"
            case .networkSaveFailed(let underlying):
                return "Network error during save: \(underlying.localizedDescription)"
            case .unsupportedSaveAs:
                return "Save As is not yet supported for PortableMind documents. Use the PortableMind web UI to rename or move; the editor will pick up the change. (A future deliverable will add Save As + New File for PortableMind.)"
            }
        }
    }

    /// Save the current buffer. Routes by origin:
    /// - `.local` → atomic UTF-8 write through the watcher-stop guard
    ///   (D14 behavior, unchanged).
    /// - `.portableMind` → `connector.saveFile(node, bytes:, force:)`;
    ///   updates `connectorNode` (refreshed `lastSeenUpdatedAt`) and
    ///   `lastSavedSource` on success.
    ///
    /// `force == true` (D19 phase 4) skips the optimistic conflict
    /// check on PM tabs. Has no effect for Local.
    func save(force: Bool = false) async throws {
        if isReadOnly { throw SaveError.readOnly }
        if isSaving { return }   // debounce concurrent saves on the same tab

        switch origin {
        case .local:
            guard let url else { throw SaveError.noURL }
            try writeAndRewatch(url: url)
            lastSavedSource = source

        case .portableMind:
            guard let node = connectorNode else {
                throw SaveError.readOnly   // shouldn't happen — PM tabs always have a node
            }
            isSaving = true
            defer { isSaving = false }
            do {
                let snapshot = source
                let bytes = Data(snapshot.utf8)
                let updatedNode = try await node.connector.saveFile(
                    node, bytes: bytes, force: force)
                connectorNode = updatedNode
                lastSavedSource = snapshot
            } catch let cerr as ConnectorError {
                switch cerr {
                case .writeForbidden(let body):
                    isReadOnly = true
                    throw SaveError.writeForbidden(body)
                case .storageQuotaExceeded(let body):
                    throw SaveError.storageQuotaExceeded(body)
                case .network(let underlying):
                    throw SaveError.networkSaveFailed(underlying)
                default:
                    throw cerr
                }
            }
        }
    }

    /// Save As. Local: writes to a new URL (D14). PortableMind: throws
    /// `.unsupportedSaveAs` per Q4 decision; the unified PM file-
    /// management deliverable (post-D20) handles rename / move /
    /// new-file.
    func saveAs(to newURL: URL) throws {
        if isReadOnly { throw SaveError.readOnly }
        if case .portableMind = origin {
            throw SaveError.unsupportedSaveAs
        }
        try writeAndRewatch(url: newURL)
        self.url = newURL
        self.lastSavedSource = source
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
