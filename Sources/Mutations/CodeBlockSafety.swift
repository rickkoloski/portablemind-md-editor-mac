import AppKit
import Foundation

/// Guards: if the caret / selection-start is inside a fenced code
/// block, formatting mutations are no-ops. Engineering-standards
/// adjacent (per `docs/current_work/specs/d04_mutation_primitives_spec.md`
/// §3 Open Question 5, probing start-of-selection covers the common
/// case at near-zero cost).
enum CodeBlockSafety {
    static func isInsideCodeBlock(selectionStart: Int, in storage: NSTextStorage) -> Bool {
        guard storage.length > 0 else { return false }
        let probe = min(max(0, selectionStart), storage.length - 1)
        let bg = storage.attribute(.backgroundColor, at: probe, effectiveRange: nil) as? NSColor
        return bg == Typography.codeBackground
    }
}
