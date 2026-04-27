import Foundation

/// Observable, ordered list of open `EditorDocument`s plus the focused
/// index. Single source of truth for "what's open in the workspace."
/// Views read from here; external commands (CommandSurface) call
/// into here.
@MainActor
final class TabStore: ObservableObject {
    @Published private(set) var documents: [EditorDocument] = []
    @Published var focusedIndex: Int? = nil

    var focused: EditorDocument? {
        guard let idx = focusedIndex, documents.indices.contains(idx) else { return nil }
        return documents[idx]
    }

    /// Open `fileURL` as a new tab, unless it's already open (in
    /// which case focus that existing tab). `forceNewTab = true`
    /// creates a new tab even if already open.
    @discardableResult
    func open(fileURL: URL, forceNewTab: Bool = false) -> EditorDocument? {
        if !forceNewTab,
           let existingIndex = documents.firstIndex(where: { $0.url == fileURL }) {
            focusedIndex = existingIndex
            return documents[existingIndex]
        }
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        let type: any DocumentType = DocumentTypeRegistry.shared.type(for: fileURL)
            ?? MarkdownDocumentType()
        let doc = EditorDocument(url: fileURL, source: source, documentType: type)
        let insertIndex = (focusedIndex.map { $0 + 1 }) ?? documents.count
        documents.insert(doc, at: insertIndex)
        focusedIndex = insertIndex
        return doc
    }

    /// Open a document that has no local file backing it (PortableMind
    /// read-only). De-dupes on origin so re-clicking the same PM file
    /// re-focuses the existing tab.
    @discardableResult
    func openReadOnly(content: String,
                      origin: EditorDocument.Origin) -> EditorDocument {
        if case .portableMind(let cid, let fid, _) = origin,
           let existingIndex = documents.firstIndex(where: {
               if case .portableMind(let xcid, let xfid, _) = $0.origin {
                   return xcid == cid && xfid == fid
               }
               return false
           }) {
            focusedIndex = existingIndex
            return documents[existingIndex]
        }
        let type: any DocumentType = MarkdownDocumentType()
        let doc = EditorDocument(url: nil,
                                 source: content,
                                 documentType: type,
                                 isReadOnly: true,
                                 origin: origin)
        let insertIndex = (focusedIndex.map { $0 + 1 }) ?? documents.count
        documents.insert(doc, at: insertIndex)
        focusedIndex = insertIndex
        return doc
    }

    /// Close the tab for document `id`. Moves focus to the neighbor
    /// on the right, falling back to the left.
    func close(id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let wasFocused = focusedIndex == index
        documents.remove(at: index)

        if documents.isEmpty {
            focusedIndex = nil
            return
        }

        if wasFocused {
            focusedIndex = min(index, documents.count - 1)
        } else if let current = focusedIndex, current > index {
            focusedIndex = current - 1
        }
    }

    func focus(id: UUID) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            focusedIndex = index
        }
    }

    func focusNext() {
        guard let current = focusedIndex, !documents.isEmpty else { return }
        focusedIndex = (current + 1) % documents.count
    }

    func focusPrevious() {
        guard let current = focusedIndex, !documents.isEmpty else { return }
        focusedIndex = (current - 1 + documents.count) % documents.count
    }
}
