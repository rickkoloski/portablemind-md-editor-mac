import AppKit
import Foundation

/// One attribute assignment: a range in the full text buffer and the
/// attributes to apply to that range. A `DocumentType.render(_:)` call
/// produces a list of these; the text view applies them inside a
/// single begin/endEditing block.
struct AttributeAssignment {
    let range: NSRange
    let attributes: [NSAttributedString.Key: Any]
}

/// Classification of a range for the cursor-on-line reveal. Delimiters
/// (markdown `**`, `*`, `` ` ``, `#`, fence lines, etc.) want to toggle
/// visibility when the caret enters or leaves a line.
enum SyntaxRole {
    case delimiter
    case rendered
}

/// A span tagged with its role, produced alongside AttributeAssignments.
/// The cursor tracker consults these to know what to toggle.
struct SyntaxSpan {
    let range: NSRange
    let role: SyntaxRole
}

/// The output of `DocumentType.render(_:)` — shared across the
/// document-type registry so future types (JSON, YAML, workflow graphs)
/// can plug in without markdown-specific coupling.
///
/// **D17**: `attributedString` is the canonical render output. The
/// editor coordinator calls `textStorage.setAttributedString(...)`
/// with this value; storage is replaced wholesale, not incrementally
/// patched. `assignments` and `spans` remain for the cursor-line
/// tracker and any document type that still wants the
/// attribute-merging path; markdown produces both for back-compat.
struct RenderResult {
    let assignments: [AttributeAssignment]
    let spans: [SyntaxSpan]
    let attributedString: NSAttributedString
}
