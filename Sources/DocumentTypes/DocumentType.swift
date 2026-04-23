import Foundation

/// A document type describes how to render a particular kind of file.
/// Principle 3 (`docs/vision.md`): markdown is the first type; JSON,
/// YAML, workflow graphs, and other structured formats plug in later.
/// Keep the editor core type-agnostic; type-specific behavior lives
/// in conformers.
protocol DocumentType {
    /// File extensions this type handles, lowercased, without the dot.
    static var fileExtensions: [String] { get }

    init()

    /// Parse `source` and return a `RenderResult` (attribute assignments
    /// plus syntax spans for the cursor-on-line tracker).
    func render(_ source: String) -> RenderResult
}
