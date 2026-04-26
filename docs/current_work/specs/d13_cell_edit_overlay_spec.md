# D13: Cell-Edit Overlay — Specification

**Status:** Draft
**Created:** 2026-04-25
**Author:** Rick (CD) + Claude (CC)
**Supersedes (in-place caret/selection only):** D12's in-cell caret + selection rendering. Underlying `cellRanges`, `CellSelectionDataSource`, double-click reveal, cell-boundary keyboard nav all stay.
**Traces to:** `docs/vision.md` Principle 1 (Word/Docs-familiar authoring); D12's wrapped-cell architectural finding (NSTextLineFragment contiguous-range constraint blocks per-visual-line caret in multi-cell rows); CD direction 2026-04-25 ("If this can't be fixed, I'm not sure I won't abandon the project").

---

## 1. Problem statement

D12 ships per-cell caret and selection that work correctly for **single-line** cell content. Wrapped cell content has two visible bugs:

1. **Right-arrow advances source position into the wrapped portion, but the caret stays visually on visual-line 1** (or jumps into the next cell visually because `caretX` exceeds column width). Users see the caret disappear or wander.
2. **Click on visual-line-2 of a wrapped cell** routes to a visual-line-1 source offset (because the unwrapped CT x-mapping puts wrapped-portion chars past column width; NSTextView picks the closest in-line match). Users see the click do nothing useful.

Root cause: NSTextView's caret y is determined by `NSTextLineFragment` geometry. Each line fragment requires a **contiguous source range**. For a multi-cell row where one cell wraps:

- Visual line 1 contains source from cell A (line-1 portion) + cell B (full content) + delimiters.
- Visual line 2 contains source only from cell A (wrapped portion).

These ranges are non-contiguous and overlap (in cell A's territory). `NSTextLineFragment` cannot represent this. There is no clean TextKit 2 way to make the caret traverse visually-wrapped cell lines while keeping the row as one source line.

Note the spike (`spikes/d12_cell_caret/`) confirmed this empirically.

---

## 2. Approach: cell-edit overlay

On click in a cell, position a reusable **overlay text view** at the cell's bounds, copy the cell's source content into it, and let the user edit there. On commit (focus loss / Tab / Enter / Escape / scroll), splice the overlay's text back into the main NSTextStorage at the cell's source range. Hide the overlay.

This matches Numbers / Excel / Google Docs cell-editing pattern (single in-place edit context per active cell). The overlay is a normal `NSTextView` — wrapping, caret traversal across visual lines, selection rendering, copy/paste, undo grouping all work natively because we're sidestepping the TextKit-2-source-fragment-model for the duration of the edit.

### 2.1 Why an overlay (and not per-cell text views always)

- **One** overlay shared across cells: cheap. Show on click, hide on commit.
- Avoids massive refactor where every cell is a sub-view (1–2 weeks of work).
- Reuses every D12 component: cellRanges, CellSelectionDataSource (for routing the initial click), TableLayoutManagerDelegate (for cell-grid render), TableRowFragment (still draws non-active cells).
- Selection within a cell is the overlay's native selection.
- Escape gives explicit cancel — important for a markdown source-of-truth model.

---

## 3. Design

### 3.1 New types

| Type | Role |
|---|---|
| `CellEditOverlay` (NSTextView subclass) | The reusable overlay. Configured per-show with cell content + frame. Holds a delegate for commit/cancel callbacks. |
| `CellEditController` (Coordinator-owned) | Owns the lifetime of the overlay. Show / hide / commit / cancel logic. Wires scroll observation. |

### 3.2 Show flow

When `LiveRenderTextView.mouseDown` (or in a single-click route within `CellSelectionDataSource`) detects a click on a `TableRowFragment`'s cell:

1. Compute the cell's view-coord rect:
    - Layout fragment frame is in container coords.
    - Add `textContainerInset` to convert to text-view coords.
    - Cell content area within the fragment: `(layout.columnLeadingX[col] - cellInset.left, ...top, contentWidths[col] + cellInset.left + cellInset.right, fragment.height)`.
    - Convert to view coords (no further offset; layout fragment frame is already in container coords which is the text-view content area).
2. Compute the click-to-caret position via the math in §3.5.
3. Hand the cell's content + computed local caret index + commit callback to `CellEditController`.
4. Controller positions the overlay at the cell rect, sets its content (the cell's pre-rendered NSAttributedString), sets `selectedRange = NSRange(location: localCaretIndex, length: 0)`, and makes it first responder.
5. Underlying `LiveRenderTextView` does NOT process the click further (no caret placement in main view).

### 3.3 Commit flow

Triggers: focus loss, Tab / Shift+Tab, Enter (single-line cells; configurable), click outside the overlay, scroll event in the host scroll view.

1. Overlay's text content is the new cell content (as a plain string, with markdown-meaningful chars preserved verbatim).
2. Replace the cell's source range in the main NSTextStorage with the new content. Pipe-escape any literal `|` characters in the new content (`|` → `\|`) so the row's structural pipes aren't disrupted by typed content. Newlines in content replaced with single spaces (one cell = one source line; multi-line cell content uses `<br>` per GFM convention if needed — out of scope for V1).
3. Hide the overlay.
4. Trigger `renderCurrentText` so the grid re-renders with the updated source.

### 3.4 Cancel flow

Triggered by Escape. Discards overlay edits without writing back. Hide overlay. Caret returns to where it was before the show (or to the cell's source-content-start, TBD).

### 3.5 Click-to-caret math

```
1. Click in view coords (cx, cy).
2. Convert to cell-content-local coords (relative to the cell's content area,
   i.e., inside the cellInset):
     relX = cx - (cellOriginX + cellInset.left)
     relY = cy - (cellOriginY + cellInset.top)
3. Layout the cell's NSAttributedString via CTFramesetter
   into a path of size (columnWidth × ∞).
4. Stack CTLines from the top, accumulating per-line height
   (ascent + descent + leading):
     accumulatedY = 0
     for each line:
       lineHeight = lineAscent + lineDescent + lineLeading
       if relY >= accumulatedY && relY < accumulatedY + lineHeight:
         localCharIndex = CTLineGetStringIndexForPosition(line, CGPoint(x: relX, y: 0))
         return localCharIndex
       accumulatedY += lineHeight
5. If no line matched (click below all lines), snap to last char:
     return cell.content.length
6. Edge case: click above first line (in cellInset.top region):
     return 0
```

Because the overlay uses the **same font, same column width, same wrapping**, its own CTLine breaks match the cell rendering's. Setting `overlay.selectedRange.location = localCharIndex` produces a caret visually at the click position.

The reverse direction (caret position → screen coords, used for setting up the overlay's initial caret and for selection-highlight rendering) is the existing `TableLayout.charXOffset` plus the per-line stacking we already use in `TableRowFragment.drawSelectionHighlight`.

### 3.6 Coordinate system handling under scroll

Two options:

**A. Hide overlay on scroll** (V1 default). The host `NSScrollView` posts `NSScrollView.didLiveScrollNotification`; controller hides the overlay (treating as commit). Simple, robust. User redoes the click after scrolling. Acceptable for non-power scenarios.

**B. Track cell position dynamically.** Listen for scroll, update overlay frame to follow the cell. More work, more edge cases (overlay leaving the visible area, overlay overlapping the document edge). Skip in V1.

V1: use option A.

### 3.7 Visual continuity

The overlay must look identical to the cell it replaces during the brief moment the cell is "selected for edit":

- Same font (`TableLayout.bodyFont` for body cells, `headerFont` for header cells).
- Same `foregroundColor` (NSColor.labelColor).
- No border on the overlay (the cell's grid-divider already provides the visual frame).
- Same vertical alignment (top-padded by `cellInset.top`).
- White / clear background (matches the cell's lack-of-fill).
- Caret color matches NSTextView default insertion point.

Acceptance: a screenshot taken with the overlay over a cell should be visually indistinguishable from the cell as it would appear without the overlay (modulo the active caret).

### 3.8 Multi-cell selection

Out of scope for V1. While the overlay is active, the user is editing a single cell. To select across cells, they must commit (Escape or click out) and use a different mechanism. Drag-select across cells in grid mode is a future polish.

### 3.9 Reveal mode interaction

Double-click still drops to whole-row source mode (D12). Overlay shows on **single-click** only. If a row is currently in source-reveal mode, single-click in that row goes through normal NSTextView click handling (no overlay).

### 3.10 What stays from D12

- `TableLayout.cellRanges` — used for source-range splice on commit.
- `TableLayout.cellContentPerRow` — used as the overlay's initial content.
- `TableLayout.charXOffset` — still useful for selection-highlight in non-active cells (D12's per-CTLine highlight remains for selections that aren't the active edit).
- `CellSelectionDataSource` — handles single-click hit-testing to determine which cell was clicked. The "snap caret to cell content" path is REPLACED by the overlay show. Remove that piece; keep the cell-detection.
- `TableRowFragment.drawSelectionHighlight` — kept for non-overlay selections (e.g., cross-cell selections built up from previous edits, programmatic selections). The overlay's own selection isn't drawn through this path — the overlay paints its own.
- `TableLayoutManagerDelegate.revealedTables` — unchanged. Reveal mode still works.
- Cell-boundary keyboard nav (Tab, arrow keys, Backspace/Delete) — applies BETWEEN cells when no overlay is active. When overlay is active, the overlay handles its own keyboard. Tab inside overlay either inserts a tab character (probably not — too invasive in markdown source) or commits + advances to next cell.

### 3.11 Undo / redo

The overlay's edits become part of the main `NSUndoManager`'s history once committed. One commit = one undoable operation: replace cell's source range with new content, or restore via inverse. Mid-edit (before commit), undo within the overlay undoes character-level changes in the overlay's local storage; that's fine.

---

## 4. Success criteria

- [ ] **Single-click in a single-line cell** → overlay appears at the cell's bounds with caret at the click position; user can type, navigate within the cell with arrows, and commit by pressing Escape, Tab, or clicking out.
- [ ] **Single-click on visual-line-2 of a wrapped cell** → overlay appears with caret on the wrapped line at the click x. User can edit anywhere in the cell. (THE primary D13 use case.)
- [ ] **Click anywhere in cell while overlay is already active in another cell** → first commit fires, then second show. No interleaved state.
- [ ] **Tab / Shift+Tab inside overlay** → commits current cell, opens overlay on next/prev cell. Caret at start of the new cell.
- [ ] **Escape** → cancels (discards overlay edits) and returns focus to main editor.
- [ ] **Scroll while overlay active** → commits the overlay (V1 simple behavior).
- [ ] **Visual** — overlay appearance is indistinguishable from cell rendering except for the active caret.
- [ ] **Double-click** still drops to whole-row source mode (no regression).
- [ ] **D8 grid rendering, D9 scroll-to-line, D10 line numbers, D11 CLI view-state, D12 cell-boundary nav between cells (no overlay active) all still work**.
- [ ] `grep -r '\.layoutManager' Sources/` shows no new production references (§2.2).

---

## 5. Implementation steps (high-level — plan has detail)

1. **Spike** at `spikes/d13_overlay/` — bounded 1-day timebox. Validate:
   - Overlay show/hide lifecycle.
   - Click-to-caret math for wrapped cells (the primary unknown).
   - Visual continuity (does the overlay actually look identical?).
   - Commit splice: pipe-escape, source replacement, re-render.
   - Scroll-during-edit behavior.
2. **`CellEditOverlay`** — NSTextView subclass with a closed configuration API.
3. **`CellEditController`** — held by `EditorContainer.Coordinator`. Show / hide / commit / cancel methods. Owns the overlay instance.
4. **Integration in `LiveRenderTextView.mouseDown`** — single-click on a `TableRowFragment` cell now triggers `controller.showOverlay(forCellAt: ..., clickPoint: ...)`. D12's `snapCaretToCellContent` removed (replaced by the overlay).
5. **Click-to-caret math helper** — new method on `TableLayout` (or free function in `Tables/`): `localCharIndex(forPoint: CGPoint, rowIdx: Int, colIdx: Int) -> Int`.
6. **Pipe-escape on commit** — apply to the overlay's text before splicing into source. `\|` → `|` on cell content load (so the user sees `|` in the overlay), `|` → `\|` on commit (so the source remains structurally valid).
7. **Tab navigation across overlay boundaries** — Tab while in overlay commits + opens next cell's overlay.
8. **Scroll observer** — `NSScrollView.willStartLiveScrollNotification` / `didLiveScrollNotification` → controller commits + hides.
9. **Manual test plan** at `docs/current_work/testing/d13_cell_edit_overlay_manual_test_plan.md` — mirrors D12's structure with overlay-specific scenarios.
10. **D12 COMPLETE doc** updated with supersession note ("D12's in-cell caret + selection superseded by D13 cell-edit overlay; cellRanges + CellSelectionDataSource + double-click reveal retained").
11. **D13 COMPLETE doc**, roadmap update, Harmoniq backlog update.

---

## 6. Open questions

- **Q1:** Tab inside overlay — commit + next cell, or insert tab into cell content? Markdown tables don't typically have tab chars in cells. Recommend: commit + next cell. Rationale: matches Numbers/Excel.
- **Q2:** Enter inside overlay — commit + below-cell (move to next row)? Or insert newline (which becomes `<br>` in GFM)? V1: commit + next-row first cell (matches Numbers).
- **Q3:** Empty cell click — should the overlay show with caret at position 0? Or use D12's snap-to-cell-content? Recommend: show overlay with empty content; user types directly. Cleaner.
- **Q4:** What happens if the user clicks INSIDE the overlay area (e.g., to move caret within the same cell)? The overlay's own click handling takes over — standard NSTextView behavior. No commit.
- **Q5:** Does the overlay need its own first-responder management, or does NSTextView's natural focus chain handle it? Probably the latter; verify in the spike.
- **Q6:** How does the overlay interact with the harness `dump_state` action? Current dump shows the main text view's selection. With overlay active, should `dump_state` report the overlay's content + selection? V1: yes, add an `overlayActive: Bool`, `overlayContent`, `overlaySelection` to the harness payload when overlay is showing.
- **Q7:** What happens to the D12 single-click `snapCaretToCellContent`? D13 replaces it. Remove on merge.
- **Q8:** Does the overlay need to support markdown delimiter reveal inside (e.g., type `**` and see it become bold)? V1: no, cell content is plain text with the existing limitations of D8's cell renderer (no inline markdown rendering inside cells). This is consistent with D8/D12's deferred scope.
