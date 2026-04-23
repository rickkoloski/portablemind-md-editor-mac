import Foundation

/// Registry for `DocumentType` implementations. Markdown is registered
/// at initialization. Future types register via `register(_:)` — likely
/// from a central place at app startup so registration isn't scattered.
final class DocumentTypeRegistry {
    static let shared = DocumentTypeRegistry()

    private struct Entry {
        let extensions: [String]
        let make: () -> any DocumentType
    }

    private var entries: [Entry] = []

    private init() {
        register(MarkdownDocumentType.self)
    }

    func register<T: DocumentType>(_ type: T.Type) {
        entries.append(Entry(extensions: T.fileExtensions, make: { T() }))
    }

    /// Returns an instance of the DocumentType matching the file's
    /// extension, or nil if no type is registered for it.
    func type(for fileURL: URL) -> (any DocumentType)? {
        let ext = fileURL.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return entries.first(where: { $0.extensions.contains(ext) })?.make()
    }
}
