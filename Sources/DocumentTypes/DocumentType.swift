import CoreGraphics
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
    ///
    /// - Parameter viewportWidth: text container width in points, used by
    ///   document types that lay out responsive content (e.g., D24 markdown
    ///   tables). Types that don't care can ignore. Default 800pt fallback
    ///   for callers without a live container measurement (rendering tests,
    ///   pre-attach paths).
    func render(_ source: String, viewportWidth: CGFloat) -> RenderResult
}

extension DocumentType {
    /// Backwards-compatible default for callers that don't pass a viewport.
    func render(_ source: String) -> RenderResult {
        render(source, viewportWidth: 800)
    }
}
