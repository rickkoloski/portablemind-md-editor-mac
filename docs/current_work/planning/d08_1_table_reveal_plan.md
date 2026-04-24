# D8.1: Table Reveal on Caret-In-Range — Implementation Plan

**Spec:** `d08_1_table_reveal_spec.md`
**Created:** 2026-04-23 evening

---

## Overview

Tie the existing `TableLayoutManagerDelegate` decision to a `revealedTables` set keyed by `TableLayout` object identity. Update the set on selection change in the coordinator; invalidate the corresponding source ranges so `NSTextLayoutManager` re-calls the delegate and gets either a `TableRowFragment` or a default fragment.

---

## Prerequisites

- [ ] D8 grid rendering on `main` (landed 2026-04-23 evening, commit `99dc2a9`).
- [ ] Verify build green before starting.

---

## Implementation Steps

### Step 1: Expose the table's full source range on `TableLayout`

**Files:** `Sources/Editor/Renderer/Tables/TableLayout.swift`

Add `let tableRange: NSRange` to `TableLayout`. Pass it through the initializer.

### Step 2: Populate `tableRange` at render time

**Files:** `Sources/Editor/Renderer/MarkdownRenderer.swift`

In `visitTable`, pass the clamped `tableRange` NSRange into the `TableLayout.init`. The table's overall range is already computed (`tableRange` local); just plumb it through.

### Step 3: Add reveal state to the delegate

**Files:** `Sources/Editor/Renderer/Tables/TableLayoutManagerDelegate.swift`

```swift
var revealedTables: Set<ObjectIdentifier> = []
```

Update `textLayoutManager(_:, textLayoutFragmentFor:in:)`:
- If the paragraph has a `TableRowAttachment` AND `revealedTables` contains `ObjectIdentifier(attachment.layout)` → return a default `NSTextLayoutFragment` (not the custom one).
- Otherwise → return `TableRowFragment` as today.

### Step 4: Observe caret changes

**Files:** `Sources/Editor/EditorContainer.swift`

Add to Coordinator:
```swift
var revealedTableLayoutID: ObjectIdentifier? = nil
```

Extend `textViewDidChangeSelection(_:)`:
1. Get caret offset from `textView.selectedRange().location`.
2. Clamp to `textStorage.length`.
3. Look up `TableAttributeKeys.rowAttachmentKey` at that offset (if any).
4. Compute `newLayoutID = attachment.map { ObjectIdentifier($0.layout) }`.
5. If `newLayoutID == revealedTableLayoutID` → no-op.
6. Else:
   - If old ID non-nil → remove from `delegate.revealedTables` + invalidate its `tableRange`.
   - If new ID non-nil → add to `delegate.revealedTables` + invalidate its `tableRange`.
   - Store `revealedTableLayoutID = newLayoutID`.

For invalidation, use:
```swift
let tr = textLayoutManager.textContentManager?.textRange(for: nsRange)
textLayoutManager.invalidateLayout(for: tr)
```

(Where `nsRange` is the `layout.tableRange` for each affected table.)

### Step 5: Build + dogfood

- `./scripts/md-editor docs/roadmap_ref.md`
- Click inside a table cell → source appears, caret positioned correctly.
- Type → source updates, grid re-renders after rerender cycle (expected).
- Arrow-down out of the table → grid returns.
- Click a different table → first table grid returns, second reveals.

### Step 6: COMPLETE doc + roadmap + commit + push

---

## Testing

### Manual

1. Open `roadmap_ref.md`. Confirm grid renders.
2. Click inside Deliverable column of any row. Confirm source (pipes, content) appears for the whole table.
3. Type a character inside a cell. Confirm it appears.
4. Arrow-up or -down to leave the table. Confirm grid returns with edit.
5. Open `competitive-analysis.md` (has multiple tables). Confirm each reveals independently.
6. Undo/redo inside a revealed table. Confirm both work.

### Regression

- D8 grid still renders (read-only view).
- D9 scroll-to-line still works.
- D10 line numbers still toggle.
- D11 CLI view state still works.
- Delimiter reveal (cursor-on-line for `#`, `**`, etc.) still works.

---

## Verification checklist

- [ ] `grep -r '\.layoutManager' Sources/` returns no new hits.
- [ ] Reveal flip is visually flicker-free.
- [ ] Two tables reveal independently.
- [ ] Edit inside revealed table persists and re-renders.
