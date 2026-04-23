import Foundation

/// Markdown — the first registered DocumentType. Wraps the renderer
/// behind the DocumentType protocol so the editor core doesn't know
/// about `MarkdownRenderer` directly.
struct MarkdownDocumentType: DocumentType {
    static let fileExtensions = ["md", "markdown"]

    private let renderer = MarkdownRenderer()

    init() {}

    func render(_ source: String) -> RenderResult {
        renderer.render(source)
    }
}
