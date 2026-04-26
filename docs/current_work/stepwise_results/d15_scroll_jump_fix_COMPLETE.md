# D15: Scroll Jump on Typing — COMPLETE

**Shipped:** 2026-04-26 in commit `a92d3e0`
**Type:** Bug fix (no full triad — small enough that spec/plan/prompt would be overhead)

---

## The bug

CD reported during D13 manual testing 2026-04-26:
> When typing in a window long enough to require a scrollbar, after I typed a space between words, the scroll position would jump. Maybe because it was jumping from edit to render mode?

Verified via harness reproduction:
- Open `docs/roadmap_ref.md` (11336 chars, scrollable).
- Scroll to Y=600.
- Set selection to a middle offset.
- Type a single space.
- **Scroll Y jumps from 600 → 1247.5** (>600 pt jump on a single keystroke).

---

## Cause

`Coordinator.renderCurrentText(in:)` ran `setAttributes(...)` on the **full text storage** every text change (via `textDidChange`). This caused TextKit 2 to invalidate and re-fragment the entire document, which in turn caused the scroll view's idea of the visible region to reset based on TextKit's layout-pass output rather than preserving the user's prior scroll position.

Worth noting: this is a known cost of "live render the whole document on every keystroke." A more incremental renderer (only re-attribute the affected line range) would avoid the issue at the source. That's a future optimization; for now we patch the symptom.

---

## Fix

Capture scroll Y BEFORE the `setAttributes`, restore it on the next runloop tick (after layout settles). Clamp restored Y to `[0, maxScrollY]` to avoid overshoot when text is deleted.

```swift
let preservedScrollY: CGFloat? = textView.enclosingScrollView
    .map { $0.contentView.bounds.origin.y }

textStorage.beginEditing()
// ... existing setAttributes + addAttributes loop ...
textStorage.endEditing()

cursorTracker.invalidate()
cursorTracker.collapseAllDelimiters(in: textView)
cursorTracker.updateVisibility(in: textView)

if let scrollView = textView.enclosingScrollView,
   let target = preservedScrollY {
    DispatchQueue.main.async {
        let docHeight = scrollView.documentView?.frame.size.height
            ?? scrollView.contentView.bounds.size.height
        let visibleH = scrollView.contentView.bounds.size.height
        let maxY = max(0, docHeight - visibleH)
        let clampedY = min(max(0, target), maxY)
        scrollView.contentView.scroll(to: NSPoint(
            x: scrollView.contentView.bounds.origin.x,
            y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
```

---

## Verification

Repeated the reproduction with the fix in place:

```
=== before insert: scrollY=600
=== insert space: scrollY=600 (was 1247)
=== insert 6 more chars (a, b, c, d, space, e): scrollY=600
```

Position holds across multiple inserts including spaces.

---

## Files modified

- `Sources/Editor/EditorContainer.swift` — `renderCurrentText` save+restore.
- `Sources/Debug/HarnessCommandPoller.swift` — `scroll_info`, `set_scroll`, `insert_text` actions for headless reproduction.

---

## Future work

The proper fix is incremental rendering: only re-attribute the affected line range when text changes, not the entire storage. That would solve scroll jump as a side effect AND drop renderer cost from O(doc length) to O(line length) per keystroke. Tracked as a future optimization candidate; not blocking.
