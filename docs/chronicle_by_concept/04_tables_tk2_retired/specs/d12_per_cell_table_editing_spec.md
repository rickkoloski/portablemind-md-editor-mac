# D12: Per-Cell Table Editing — Specification

**Status:** Draft
**Created:** 2026-04-24
**Author:** Rick (CD) + Claude (CC)
**Supersedes (primary path):** D8.1's single-click → whole-table source reveal. See §3.6.
**Depends on:** D8 (grid rendering via `TableRowFragment`), D8.1 (whole-table source-mode machinery — repurposed, not removed).
**Traces to:** `docs/vision.md` Principle 1 (Word/Docs-familiar authoring); `docs/current_work/specs/d08_1_table_reveal_spec.md` §2 (out-of-scope deferral that's being promoted); Harmoniq project #53 task #1386.

---

## 1. Problem Statement

D8.1 shipped whole-table reveal on caret-in-range: click anywhere in a table → the whole table flips to pipe-delimited source, caret lands at the source character offset. Functional, but wrong UX:

- **Jarring mode switch** — single click shouldn't re-render the whole table.
- **Caret mispositioned** — with source still present under the grid, NSTextView draws the caret at the source character's horizontal position, which can land far outside the grid's visible bounds (observed: caret drawn to the right of the viewport while typed text appears inside the cell after re-render).
- **Not matched to expectation** — the vast majority of table edits are cell-scoped (change a value in one cell, fix a typo, update a status). Users expect to click a cell and edit it, the way Word / Docs / Numbers tables work.

D12 makes single-click place the caret **inside the clicked cell**, type goes into that cell only, and the rest of the grid stays rendered the whole time. Whole-table source editing is retained as a secondary power path, triggered by double-click.

---

## 2. Requirements

### Functional — cell-level editing (primary)

- [ ] **Single-click inside a grid cell** places the caret at the corresponding character position inside that cell. The grid continues to render; no mode switch.
- [ ] **Caret is drawn at the cell's visual position and at natural line height**, not at the underlying source character's horizontal position and not at the full grid-row height. Caret appearance, blink, selection highlight all behave Word/Docs-like.
- [ ] **Typing** inserts at the caret's cell position. The inserted characters land at the correct source offset (inside the cell's pipe-delimited source range). The grid re-renders with the edit; caret stays visually in the cell.
- [ ] **Backspace / Delete** operate on the cell's source content. Backspace at column 0 of the cell moves to the previous cell's end (not into the pipe character); Delete at end-of-cell moves to next cell's start. Cell boundaries are navigable, but pipe characters are not directly edited.
- [ ] **Tab** moves caret to next cell's start; **Shift+Tab** moves to previous cell's end.
- [ ] **Left/Right arrow** — move within the cell until the cell boundary; then cross to the adjacent cell (Word/Docs behavior).
- [ ] **Up/Down arrow** — if the cell has wrapped content, move between wrapped lines within the cell; at top/bottom of cell, move to the cell directly above/below; at top row, move to paragraph before the table; at last row, move to paragraph after the table.
- [ ] **Selection within a cell** renders as a normal text selection constrained to the cell's visual bounds.
- [ ] **Multi-cell selection via drag** (drag from cell A to cell C) renders per-cell selection highlights in the intervening cells. Copy operates on the pipe-source of the selected cells.
- [ ] **Undo / redo** — one typing session in a cell = one undo group. Matches the rest of the editor.
- [ ] **Paste** into a cell — the clipboard text replaces the cell's content (if a range is selected) or inserts at the caret. Newlines in pasted content are replaced with spaces (GFM single-line-per-cell invariant).

### Functional — whole-table source editing (secondary)

- [ ] **Double-click inside a grid cell** drops the whole table to pipe-delimited source mode (existing D8.1 mechanism). Caret positioned at the double-click location in source.
- [ ] In source mode, the entire row is a normal markdown paragraph: any edit applies; arrow-out returns to grid.
- [ ] **Caret is correctly positioned** in source mode — fixes the observed D8.1 bug where the caret drew past the viewport. See §3.5.
- [ ] **Exit source mode** — arrow / click / Escape out of the table; grid returns with the edit.
- [ ] Whole-table source mode is **explicit, not automatic**. Single-click and caret arrival via keyboard navigation never drop to source.

### Non-functional

- [ ] **No `.layoutManager` references** (engineering-standards §2.2).
- [ ] **No storage shortcuts** — source is always truth. Cell editing writes to storage at the correct source range.
- [ ] **Performance** — typing at 10 chars/sec in a cell triggers one re-render per keystroke (already the rule). No frame drops or visible flicker.
- [ ] **Accessibility** — each cell is individually focusable / readable by VoiceOver. Cell-level editing must not regress accessibility below D2's baseline.

### Out of scope

- **Inline markdown formatting inside cells** (bold/italic/link/code inside a cell's text) — still deferred; cell content is plain text from GFM source substring. Separate deliverable.
- **Cell size resizing via drag handles** — no column/row resize UX. Column widths still computed from cell content.
- **Adding / deleting rows or columns via UI** — requires grid-bound chrome. Separate deliverable.
- **Merged cells** — not in GFM spec; not supported.
- **Table-level operations menu** — copy table, convert to CSV, etc.

---

## 3. Design

### 3.1 Per-cell source range cache

`TableLayout` currently holds `cellContentPerRow: [[NSAttributedString]]` — pre-rendered cell visuals. Extend it with the inverse:

```swift
/// Per-cell source NSRange in the markdown buffer. Indexed
/// [rowIndex][columnIndex]. `cellRanges[r][c]` is the source range
/// of the cell's content — exclusive of surrounding pipes and
/// surrounding whitespace. Computed once by `MarkdownRenderer.visitTable`.
let cellRanges: [[NSRange]]
```

The renderer's existing `clampedLineRange` + cell-extraction logic already finds cell-content bounds (used by D8 Finding #5's first-line-only trimming). Reuse that to populate `cellRanges` at render time.

Edge cases in cell-range computation:
- GFM pipe-escape (`\|`) inside a cell — the escaped pipe is content, not a cell boundary. Existing renderer splits on raw pipes; this spec requires splitting on unescaped pipes.
- Cell content may be empty (`| cell1 |  | cell3 |`). The range is zero-length at the appropriate source offset. Typing into an empty cell inserts at that offset.
- Trailing pipe vs. GFM-optional trailing pipe — normalize: if the row source ends without a trailing `|`, the last cell's range extends to end-of-line.

### 3.2 Hit-testing — click to (row, column)

`NSTextView` delivers a click in its coordinate space; we need to intercept before NSTextView's default caret placement runs, and route to the cell.

Approach: override `NSTextView.mouseDown(with:)` in `LiveRenderTextView`. On each event:

1. Hit-test the click point against `NSTextLayoutManager.textLayoutFragment(for:)` to find the fragment under the click.
2. If the fragment is a `TableRowFragment`:
   - Convert click-x to column index via `layout.columnLeadingX` / `columnTrailingX`.
   - Convert click-y to whether the click is within the row's y-extent.
   - If `event.clickCount == 2`: route to D8.1's whole-table source reveal.
   - If `event.clickCount == 1`: route to cell-level caret placement (§3.3).
3. If not a table fragment: call `super.mouseDown(with:)` (default behavior).

### 3.3 Caret routing — place caret inside a cell

When a single-click lands in cell (r, c):

1. Look up `layout.cellRanges[r][c]` → `NSRange` of the cell's content.
2. Convert click-x-within-cell to a source offset inside the cell range. Strategy:
   - Take the cell's rendered `NSAttributedString` (`cellContentPerRow[r][c]`).
   - Use `CTLineCreateWithAttributedString` / `CTLineGetStringIndexForPosition` to map x-in-cell to a character offset within the cell's rendered content.
   - Add the cell range's start offset to produce the source offset.
3. Set `selectedRange(NSRange(location: sourceOffset, length: 0))`.

The caret now lives at a source character inside the cell. But NSTextView will draw it at the source character's horizontal position, which is still wrong. §3.4 fixes the drawing.

### 3.4 Caret drawing — custom `NSTextSelectionDataSource`

**Revised 2026-04-24** after Phase 1 spike. Original approach (override `NSTextLayoutFragment.textLineFragments` with custom typographic bounds) was invalidated by header reading — `NSTextLineFragment.typographicBounds` and `glyphOrigin` are readonly with no public setter path. Spike: `spikes/d12_cell_caret/FINDINGS.md`.

**Working approach:** install a custom `NSTextSelectionNavigation` on the text view's layout manager. The navigation is backed by a custom `NSTextSelectionDataSource` (a subclass / wrapper of `NSTextLayoutManager`'s own data-source conformance) that overrides two methods:

```swift
// Controls where the caret draws.
func enumerateCaretOffsetsInLineFragment(
    at location: any NSTextLocation,
    using block: (CGFloat caretOffset, any NSTextLocation, Bool leadingEdge,
                  UnsafeMutablePointer<ObjCBool>) -> Void)

// Controls click → source-range hit-testing.
func lineFragmentRange(for point: CGPoint,
                       inContainerAt location: any NSTextLocation) -> NSTextRange?
```

For a table row:

- **`enumerateCaretOffsetsInLineFragment`** yields (caret-x, source-location) pairs in strict left-to-right visual order. For each source character inside a cell's range, it yields `caretX = cell's columnLeadingX + offsetWithinCell * cell's per-char x stride`. Pipe characters and inter-cell whitespace get small stub x-values outside the cell geometry (acts as a narrow "dead zone" between cells). Multi-line cells yield multiple enumerations, one per wrapped visual line.
- **`lineFragmentRange`** hit-tests click points against each cell's geometry. If `point` falls inside cell (r, c)'s bounds, return an `NSTextRange` covering only that cell's source range. This constrains NSTextView's click-to-offset mapping to the clicked cell.

All other `NSTextSelectionDataSource` methods (`documentRange`, `enumerateSubstrings`, `locationFromLocation`, `offsetFromLocation`, `baseWritingDirection`, etc.) delegate directly to the wrapped `NSTextLayoutManager`.

**Caret height:** since the line fragment's natural `typographicBounds.height` comes from CT layout of the attributed string, and we don't attach a height-forcing paragraph style on revealed tables (per §3.5), the natural font line height is used — so the caret draws at natural (~14pt) height, not grid (~35pt) height. This fixes the D8.1 size bug.

**Spike evidence (2026-04-24):** a minimal SwiftPM reproducer installed a custom data source on a throwaway text view. `enumerateCaretOffsets` yielded monotonic x = 50 + 30·srcIdx (obviously shifted from natural CT layout). On click, the caret visually drew at the custom x-values (observed ~256 vs. declared 260 for source offset 7; natural CT layout for that offset would have been ~110). Source edits happened at the correct source offset independently of visual caret placement. GREEN. See `spikes/d12_cell_caret/FINDINGS.md` for full details.

**Fallback (not expected to be needed):** if production-scale integration (multi-row tables, wrapped cells, selection across cells) surfaces unfixable behavior in the data-source path, an NSTextField overlay per active cell is the documented fallback. Modal is explicitly parked per CD direction and memory `md_editor_d12_break_glass_fallback.md`.

### 3.5 Fixing the D8.1 source-mode caret (position AND size)

The observed caret bug in source mode has two components, same root cause:

- **Position wrong** — NSTextView draws the caret at the underlying source character's horizontal position. In revealed source mode the row's text is the full pipe-source line (`| D1 | ... | ... |`), which extends past the grid's visible width — caret lands off-screen or at the far right.
- **Size wrong** — the min/max-line-height paragraph style attached by the renderer (D8.1 Finding #2) forces the row's line fragment to be as tall as the grid cell (~35pt+). The caret follows the line fragment's height, producing a tall ruler-like caret rather than a normal ~14pt one.

Both come from the paragraph style being applied during source mode. The size bug is fixed by stripping the paragraph style (row re-flows at natural text-font line height → caret is natural height). The position bug is fixed by the same strip (line fragment is natural text geometry → caret x follows normal source-character layout within the line).

Current D8.1 implementation *does* strip paragraph style on reveal via `adjustParagraphStyles(revealed: true, ...)`, but the render-on-keystroke cycle via `renderCurrentText` re-applies it before the next `updateTableReveal` tick gets a chance to strip again. Net effect: grid-height paragraph style present during the visible frame → tall caret at source-position → the observed bug.

Fix: move the decision to the renderer. `MarkdownRenderer.visitTable` consults the current reveal set (injected via renderer context or read from an environment object held on the Coordinator) and omits `.paragraphStyle` on rows of revealed tables. The Coordinator's `adjustParagraphStyles` helper retires — reveal state becomes an input to render, not a post-render mutation.

This also fixes the caret size in cell-editing mode: cell-mode line fragments size to natural line height per §3.4, so the caret is normal-height. The two modes differ in *which* line fragments are emitted (per-cell geometry vs. default whole-row), but both converge on "no tall paragraph-style override of line height" → "normal caret."

### 3.6 Whole-table source mode trigger change

D8.1 currently triggers reveal on `textViewDidChangeSelection` — any caret landing in a table flips the table to source. D12 replaces this with an explicit double-click gesture:

- **Double-click inside a table cell** → set `delegate.revealedTables` to include that table's layout ID + invalidate (unchanged from D8.1).
- **Single-click / keyboard caret entry** → cell-level caret placement (§3.3); table stays gridded.
- **Caret exit from a revealed table** (arrow out, click outside) → un-reveal (unchanged from D8.1).

`updateTableReveal(in:)` in `EditorContainer.Coordinator` loses its "auto-reveal on caret" logic. The reveal-state machinery and `findTableRange(for:in:)` scanner stay — they're still needed for the un-reveal path and for cases where the user double-clicks a cell that's inside an already-revealed-by-different-trigger table.

Keyboard path to whole-table source mode: a menu command `Edit → Edit Table as Source` bound to a keyboard shortcut (suggest `Cmd+Shift+E`, TBD). Activates when the caret is inside a cell; reveals the containing table.

### 3.7 Cell-boundary navigation (Tab, Shift+Tab, arrows)

Overridden key bindings in `LiveRenderTextView`:

- Tab when caret is in a cell → advance to next cell's source-range start. If on last cell of last row → move to paragraph after table (Word/Docs insert-a-row behavior deferred).
- Shift+Tab → previous cell's end.
- Left arrow at cell-range start → previous cell's end (skip pipe).
- Right arrow at cell-range end → next cell's start (skip pipe).
- Up / Down arrow → up/down a visual line. Within a wrapped cell, move to same x in adjacent wrapped line. Crossing a row boundary, move to same x in the adjacent row's cell (best-effort column alignment).

### 3.8 Typing inside a cell

`NSTextView`'s default insertion path calls `NSTextStorage.replaceCharacters(in:with:)` at the selected range. With the caret at a source offset inside the cell range, this Just Works — the inserted character lands at the right source position.

After the insertion, `renderCurrentText` re-parses and re-computes `cellRanges`. The old caret location may have shifted if the cell's range grew. `NSTextView` maintains selection across storage edits by source offset (which is what we want — the caret tracks the typed character, which is now at `oldOffset + 1`). The next render places that source offset back into a cell (possibly the same cell, larger now) and the caret draws correctly per §3.4.

### 3.9 Selection rendering across cells

Selections within a single cell use default selection rendering — the line fragment for that cell handles it via TextKit's normal highlight path.

Selections that span cells (across pipes) require custom drawing: the fragment must clip the selection to per-cell regions, skipping the pipe gaps. Extend `TableRowFragment.draw(at:in:)` to consult the current selection on the layout manager and paint per-cell highlight rectangles before drawing cell content. Selection color: `NSColor.selectedTextBackgroundColor`.

### 3.10 Paste and newline normalization

Paste → `NSPasteboard.readObjects(forClasses: [NSString.self])`. If the caret is inside a cell range, replace the cell's source range with the pasted text (or insert at caret if a sub-cell range is selected), replacing `\n` with single spaces. Pipe characters in pasted content are escaped to `\|`.

Behavior on paste-into-source-mode (D8.1 path) is unchanged — regular NSTextView paste into the source buffer.

---

## 4. Success Criteria

- [ ] Open `docs/roadmap_ref.md`. Single-click on the Status cell of D5. Caret lands inside the cell. Type "(updated)". Grid stays rendered. Cell content updates live. Arrow out of the table. Grid still present, edit preserved.
- [ ] Single-click on an empty cell. Caret lands at the empty cell's source offset. Type a character. Cell shows the character; grid layout may expand column width on re-render.
- [ ] Double-click a cell. Table drops to source mode. Caret is at the correct position (not drawn past the viewport).
- [ ] Keyboard Tab from a cell advances to the next cell. Shift+Tab reverses. Left arrow at cell-start crosses to previous cell.
- [ ] Drag-select from cell (r1, c1) to cell (r3, c3). Selection rendered in per-cell highlights. Copy → clipboard contains the GFM-source cell contents in order, separated by pipes.
- [ ] Cmd+Z after typing reverts to pre-type state. Redo re-applies.
- [ ] `grep -r '\.layoutManager' Sources/` shows only existing docstring mentions; no new production references.
- [ ] D8 grid rendering unchanged when caret is not in any table.
- [ ] D9 scroll-to-line, D10 line numbers, D11 CLI view-state all still work.

---

## 5. Implementation Steps (high-level)

Detailed steps live in the plan.

1. **Spike** (bounded, ~1 day) — prove line-fragment mapping. Build a throwaway `TableRowFragment` override of `textLineFragments` returning one fragment per cell with geometric bounds matching cell positions. Click into a cell, verify NSTextView's natural caret lands in the cell. If infeasible, fall back to NSTextField overlay.
2. **Populate `cellRanges`** in `TableLayout` from renderer.
3. **Override `NSTextView.mouseDown`** to route single-click to cell caret placement, double-click to whole-table reveal.
4. **Line-fragment override** (or overlay path) in `TableRowFragment` so caret draws at cell position.
5. **Cell-boundary navigation keys** (Tab, arrows).
6. **Selection rendering across cells**.
7. **Retrigger D8.1 reveal path** — remove auto-reveal-on-caret from `updateTableReveal`; wire to double-click handler; add `Edit → Edit Table as Source` menu command.
8. **Fix D8.1 caret bug** — paragraph-style-not-applied-on-revealed-tables path per §3.5.
9. **Paste normalization** per §3.10.
10. **Undo / redo** — verify typing session groups correctly.
11. **Manual test plan** update — `docs/current_work/testing/d12_per_cell_table_editing_manual_test_plan.md` with cell-level + source-mode scenarios.
12. **COMPLETE doc**, commit, push.

---

## 6. Open Questions

- **Q1 (resolved 2026-04-24):** Hypothesis was "override `NSTextLayoutFragment.textLineFragments`." **Answer: no — `NSTextLineFragment` bounds are readonly.** Revised hypothesis: custom `NSTextSelectionDataSource`. **Answer: yes — caret x is honored.** See §3.4 and `spikes/d12_cell_caret/FINDINGS.md`.

- **Q2:** Cell-boundary navigation with arrow keys across row boundaries — "same x column" is approximate when columns have different widths. Word/Docs snap to the nearest character position; we should match. Acceptable — note the visual snap in the test plan.

- **Q3:** Keyboard shortcut for `Edit Table as Source`. `Cmd+Shift+E` conflicts with nothing in the current keyboard map but may conflict with system services. Alternative: `Cmd+Option+T`. Pick during implementation; document in engineering-standards when it ships.

- **Q4:** When the user double-clicks a cell that contains a word, macOS's default double-click behavior selects the word. Our override intercepts double-click and drops to source mode. Is word-select lost? Proposal: **single-click places caret in cell; double-click inside the CELL selects the word** (match macOS); **double-click outside any cell but inside the grid** (on borders / padding) drops to source. Revisit if the border-hit region is too small — alternative gesture: `Option+click` or a menu command only.

- **Q5:** Pipe-escape in pasted content (`\|`) — do we render the backslash visibly in the cell or hide it as an escape character? Hide — cell-content rendering strips `\` before `|`. Document the escape at source level.

- **Q6:** Multi-line cells (when a cell wraps to 2+ visual lines due to content exceeding column width). Caret up/down within the cell via arrow keys — does TextKit handle this naturally if line fragments are stacked correctly, or do we need explicit handling? Should be natural, but verify during spike.

- **Q7:** What happens during renderCurrentText if the user is actively typing and the table's structure changes (e.g., typed a pipe character `|` — now the row has an extra cell)? Edge case. Behavior: preserve caret at the post-insert source offset, let renderCurrentText produce a new `TableLayout` with revised `cellRanges`, caret lands wherever that source offset falls in the new layout. May feel jumpy; acceptable in V1.

- **Q8:** Existing D8.1 manual test plan — does it still apply after D12 changes the trigger? **No — retire it** when D12 ships. The D12 test plan replaces it, but we keep `d08_1_manual_test_plan.md` as historical reference in `chronicle_by_concept/` per CLAUDE.md.

- **Q9 (new, from spike):** `lineFragmentRangeForPoint` must return cell-scoped ranges, not row-scoped, for clicks to route to cell offsets instead of natural-CT-layout offsets. Noted in §3.4; implementation must honor this. If the override falls back to the default, NSTextView uses natural CT x to pick the offset — which is what we're trying to get away from.

- **Q10 (new, from spike):** `enumerateCaretOffsetsInLineFragment` must yield caret offsets in strict left-to-right visual order. Non-monotonic enumeration confuses NSTextView's hit-test. For GFM tables this is naturally LTR (cells rendered left-to-right), but the implementation must be explicit about it.
