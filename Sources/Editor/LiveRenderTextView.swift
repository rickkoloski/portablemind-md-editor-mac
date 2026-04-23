import AppKit
import Foundation

/// NSTextView subclass housing our TextKit 2 live-render editor.
///
/// D2 status: the spike used an unmodified `NSTextView` — we introduce
/// this subclass as the home for future view-level customization
/// (custom context menu, first-responder focus hooks, accessibility
/// overrides). Kept minimal today; populated as feature deliverables
/// call for it.
///
/// IMPORTANT (`docs/engineering-standards_ref.md` §2.2): never access
/// `.layoutManager` on this class or any `NSTextView`. Accessing it
/// lazy-creates a TextKit 1 manager and silently flips the code path.
final class LiveRenderTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
}
