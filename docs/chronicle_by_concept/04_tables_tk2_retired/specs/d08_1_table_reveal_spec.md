# D8.1: Table Reveal on Caret-In-Range — Specification

**Status:** Draft
**Created:** 2026-04-23 evening
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D8 (grid rendering via custom `NSTextLayoutFragment`)
**Traces to:** `docs/vision.md` (live-render philosophy — source is truth; reveal-on-cursor pattern); `docs/current_work/specs/d08_table_rendering_spec.md` §3.5 (reveal integration was deferred from D8 to a separate deliverable)

---

## 1. Problem Statement

D8 renders GFM tables as a visual grid via `NSTextLayoutFragment` substitution. The source text remains in the buffer, but the fragment hides it. When the caret enters the table's source range, the user cannot see what they're typing — the grid still draws and the source is invisible underneath.

D8.1 adds the reveal behavior: when the caret is inside a table's source range, **that table (or the specific row the caret is on) switches to source mode** — the custom fragment stops drawing and default text rendering returns. When the caret leaves, the grid re-renders.

This matches the pattern md-editor already uses for delimiters and code-block fences: source is truth; the rendering is a courtesy that yields to the caret.

---

## 2. Requirements

### Functional

- [ ] When the caret enters any character inside a table's source range, that table's rows switch to **source mode** — the grid fragment is replaced by the default `NSTextLayoutFragment` so the pipe-delimited source text is visible.
- [ ] When the caret leaves the table range, the table returns to **grid mode**.
- [ ] **Reveal granularity = whole table.** Caret on any row of the table reveals the entire table. This matches CodeBlock's whole-block reveal pattern and avoids the "half-rendered mid-edit" problem that per-row reveal would produce. Spec open question Q1 below.
- [ ] Editing the source in reveal mode works identically to editing any other markdown block — typing adds characters, Backspace deletes, Cmd+A selects, etc.
- [ ] Leaving the table (arrow keys, click outside, Cmd+End) re-renders the grid with the edited content. No stale cached layout.
- [ ] Multiple tables in a document each reveal independently — entering table A doesn't affect table B.

### Non-functional

- [ ] Standards §2.2 — no `.layoutManager` introduced. Invalidation via `NSTextLayoutManager.invalidateLayout(for:)`.
- [ ] Performance — caret movements within the same revealed table are free (no invalidation). Crossing a table boundary triggers one invalidation of the affected table's source range.
- [ ] No flicker on caret move within a revealed table.

### Out of scope

- Structured editing of cells (click-a-cell-to-edit-inline affordance). Edit mode is just pipe-delimited source.
- Per-row reveal (instead of whole-table reveal). Can be reconsidered if dogfood surfaces a use case.
- Animated transitions between grid and source modes.
- Reveal of just the header (e.g., "edit header names but keep body as grid").

---

## 3. Design

### 3.1 Shared reveal state

Extend `TableLayoutManagerDelegate` with a set of "currently revealed" table identities. A `TableLayout` instance identity (pointer equality on the shared object attached to every row via `TableRowAttachment.layout`) is sufficient — rows of the same table all share the same `TableLayout`.

```swift
final class TableLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    /// Tables currently in source-reveal mode. Keyed by ObjectIdentifier
    /// of the shared TableLayout. Entries are added/removed by the
    /// coordinator on selection change.
    var revealedTables: Set<ObjectIdentifier> = []

    // ... existing methods ...
}
```

### 3.2 Delegate decision

```swift
func textLayoutManager(_:, textLayoutFragmentFor:in:) -> NSTextLayoutFragment {
    if let paragraph = textElement as? NSTextParagraph,
       let attachment = tableAttachment(in: paragraph) {
        if revealedTables.contains(ObjectIdentifier(attachment.layout)) {
            // Source mode — let default rendering draw the pipes.
            return NSTextLayoutFragment(textElement: textElement,
                                        range: textElement.elementRange)
        }
        return TableRowFragment(textElement: textElement,
                                range: textElement.elementRange,
                                attachment: attachment)
    }
    return NSTextLayoutFragment(...)
}
```

### 3.3 Caret observation

`EditorContainer.Coordinator.textViewDidChangeSelection(_:)` already exists for `CursorLineTracker`. Extend it:

1. Inspect the caret's character offset.
2. Find the `TableRowAttachment` at that offset (if any) via `textStorage.attribute(TableAttributeKeys.rowAttachmentKey, ...)`.
3. Compare its `layout` to the previously-revealed layout (if any).
4. If unchanged, no-op.
5. If different (including "now nil" — caret left a table), update `delegate.revealedTables` and invalidate the affected source ranges via `textLayoutManager.invalidateLayout(for:)`.

### 3.4 Range tracking for invalidation

When toggling a table's reveal state, we need to know the source range to invalidate — i.e., the full span from the table's first row to its last row.

Options:
- Store the full `tableRange` on `TableLayout` so any attachment can produce it.
- Scan the text storage for all characters carrying the same layout attachment.

Preferred: store `tableRange` on `TableLayout` at render time. Small change; avoids a storage scan on every caret move.

### 3.5 Avoiding stale fragments after edits

When the user types inside a revealed table, `textDidChange` triggers `renderCurrentText`, which re-parses and re-applies attributes. The new `TableLayout` instance differs from the previous one by identity. On caret-out, the coordinator needs to look up the *current* layout at the boundary to know what to re-invalidate. The layout-attachment lookup from current storage handles this naturally.

### 3.6 Interaction with CursorLineTracker

`CursorLineTracker` already handles delimiter reveal (cursor-on-line) separately. Tables and delimiters don't conflict — pipes inside a revealed table become visible via the default `NSTextLayoutFragment` already (no delimiter attribute involved). The tracker doesn't need to be modified for D8.1.

---

## 4. Success Criteria

- [ ] Open `docs/roadmap_ref.md`. Click inside the roadmap table's Deliverable column. The table switches to pipe-source. Type a character — it appears in the source. Move caret out of the table (Down arrow past the last row, or click outside). Grid re-renders, including the edit.
- [ ] Caret moves within the same table (different rows, different columns) — no flicker, no re-layout cost.
- [ ] Two tables in a doc: entering table A reveals A but NOT B. Moving to B reveals B and re-hides A.
- [ ] Saving the file and reopening shows the edited content correctly.
- [ ] No `.layoutManager` references added.
- [ ] D8, D9, D10, D11 functionality all still works.

---

## 5. Implementation Steps

1. Add `tableRange: NSRange` property to `TableLayout`.
2. Populate it in `MarkdownRenderer.visitTable` — pass the table's clamped range.
3. Add `revealedTables: Set<ObjectIdentifier>` to `TableLayoutManagerDelegate`. Update delegate method to check it.
4. Add `activeRevealedTableID: ObjectIdentifier?` tracking state to `EditorContainer.Coordinator`.
5. Extend `textViewDidChangeSelection`: look up attachment at caret; compute new revealed-table-ID; diff against previous; invalidate both old and new table ranges via `textLayoutManager.invalidateLayout(for:)`.
6. Build, launch, dogfood on roadmap.
7. COMPLETE doc, commit, push.

## 6. Open Questions

- **Q1:** Whole-table reveal vs. per-row reveal. Spec picks whole-table (matches CodeBlock). Revisit if UX feels wrong.
- **Q2:** Should typing inside a revealed table preserve the caret position stably across rapid re-renders (every keystroke triggers renderCurrentText)? Default `NSTextView` behavior should handle this since source chars aren't moving. Verify during dogfood.
- **Q3:** What does reveal look like visually during selection that crosses the table boundary (e.g., Shift+click from before to after the table)? Reveal the entire table range as part of the larger selection. Trivial given "caret in table range" → reveal.
- **Q4:** Do we need an `invalidate-on-cellRenderer-change` path? Not in D8.1 — the CellRenderer protocol isn't in place yet.
