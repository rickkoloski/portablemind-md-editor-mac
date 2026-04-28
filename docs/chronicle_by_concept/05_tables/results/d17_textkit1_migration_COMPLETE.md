# D17: TextKit 1 Migration — COMPLETE

**Shipped:** 2026-04-26
**Spec:** `docs/current_work/specs/d17_textkit1_migration_spec.md`
**Plan:** `docs/current_work/planning/d17_textkit1_migration_plan.md`
**Prompt:** `docs/current_work/prompts/d17_textkit1_migration_prompt.md`
**Spike (validated):** `spikes/d16_textkit1_tables/`
**Tag:** `v0.5-tk1`

---

## What shipped

The editor's text view migrated from TextKit 2's custom-`NSTextLayoutFragment` table system to TextKit 1's native `NSTextTable` / `NSTextTableBlock`. ~3,200 lines of custom-layout machinery deleted; net code volume DOWN.

Per-phase commits:

| Phase | Commit | What |
|---|---|---|
| 1 | `a5b1aed` | Text view on explicit TK1 init (`NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView`); LineNumberRulerView ported to `NSLayoutManager.lineFragmentRect(forGlyphAt:effectiveRange:)`. |
| 1.x | `7a2b536` | Init fix: documentView resizing properties (`isVerticallyResizable`, `minSize`/`maxSize`) so the scroll view's content area is interactive. |
| 2 | `5d8536f` | Markdown renderer emits a full `NSAttributedString` with `NSTextTable` cell paragraphs; `TK1Serializer` round-trips back to markdown for source sync; cell paragraphs carry `cellSourceRangeKey` and non-cell paragraphs carry `paragraphSourceRangeKey`. |
| 3+4 | `04ac868` | Deleted: `TableRowFragment`, `TableLayoutManagerDelegate`, `TableLayout` (and `TableRowAttachment`), `CellSelectionDataSource`, `CellEditOverlay`, `CellEditController`, `CellEditModalController`. Stripped harness overlay/modal/cell actions. EditorContainer Coordinator no longer wires the TK2 setup block. LiveRenderTextView collapsed to a minimal subclass. |
| 5 | `8de55e4` | Retired `scrollSuppressionDepth` + `scrollRangeToVisible` override + `isNavigationKey` + the keyDown wrap. Stock TK1 has no auto-scroll-on-edit overshoot. |
| 6 | `8686fc8` | Cell-aware Tab/Shift+Tab nav reinstated on TK1 — detects cell paragraphs via `paragraphStyle.textBlocks` containing an `NSTextTableBlock`, walks adjacent paragraphs that share the same `NSTextTable`. Header cells participate in cycling (no exclusion). |

---

## Architecture

### Storage = rendered form, source = canonical markdown

Pre-D17: `textView.string == document.source` was a load-bearing invariant; `renderCurrentText` only added attributes.

Post-D17: storage contains the *rendered* form — pipes don't survive in the table region; each cell is its own paragraph with `paragraphStyle.textBlocks = [NSTextTableBlock]`. `document.source` is the canonical markdown (loaded from disk, written on save), maintained as a side-channel via `TK1Serializer` on every edit.

```
markdown source  ──render──►  attributed string (cell paragraphs)
                                       │
                                  user edits cells
                                       │
                                       ▼
                              TK1Serializer
                                       │
                                       ▼
                  markdown source (canonical, saved as-is)
```

### `paragraphSourceRangeKey` + `cellSourceRangeKey`

Every paragraph in storage carries a custom attribute pointing back to its slice of `document.source`. Two flavors:
- **Non-table paragraph**: `paragraphSourceRangeKey` — value is the paragraph's source range (1:1 mapping).
- **Cell paragraph**: `cellSourceRangeKey` — value is the *cell's* source range, between the markdown pipes, content only. Pipes themselves (and the row's surrounding `\n`s) are not included.

The serializer doesn't actually use these attributes; it groups cell paragraphs by their `NSTextTable` instance and emits markdown rows. The attributes are kept for future incremental-source-update optimizations and for harness diagnostics.

### renderCurrentText replaces storage entirely

`renderCurrentText` reads from `document.source` (NOT `textView.string` — they may differ for tables) and produces a new attributed string via `MarkdownRenderer.buildAttributedString`. The text storage is replaced wholesale via `setAttributedString`. Selection is preserved across the replace as best-effort (clamped to new storage length).

This path runs only on full refresh: doc open, external edit watcher firing. NOT on every keystroke — that would replace storage and reset the caret. For keystrokes:

### textDidChange syncs source incrementally, no re-render

User types → storage edits in place. `textDidChange` runs `TK1Serializer.serialize(storage)` and writes the result to `document.source`. The Combine sink on `document.$source` would normally trigger a re-render, but a `isApplyingUserEditToSource` flag short-circuits it.

So during a typing session: storage stays internally consistent (NSTextView's edit-in-place behavior), `document.source` stays canonical (serialized on every keystroke), no full re-renders, caret position never resets.

### TK1TableBuilder

Builds the cell-paragraph attributed string for one markdown table:
- One `NSTextTable` per markdown table.
- One `NSTextTableBlock` per cell, with row/col indices, padding, border.
- Column content widths computed from max natural cell width per column, capped at 320pt.
- Each cell's text un-escapes `\|` → `|` and `\\` → `\` for display.
- Paragraph terminator `\n` ends each cell.

### TK1Serializer

Walks paragraphs in storage. Groups cell paragraphs by their `NSTextTable` instance (multiple consecutive cells of the same table → one row block in markdown). For each cell, escapes `|` → `\|` and `\` → `\\` for safe round-trip. After header row, emits `| --- | --- | --- |` separator. Plain-text paragraphs pass through verbatim.

---

## Files retired (~3,200 lines deleted)

- `Sources/Editor/Renderer/Tables/TableRowFragment.swift`
- `Sources/Editor/Renderer/Tables/TableLayoutManagerDelegate.swift`
- `Sources/Editor/Renderer/Tables/TableLayout.swift` (also held `TableRowAttachment`)
- `Sources/Editor/Renderer/Tables/CellSelectionDataSource.swift`
- `Sources/Editor/Renderer/Tables/CellEditOverlay.swift`
- `Sources/Editor/Renderer/Tables/CellEditController.swift`
- `Sources/Editor/Renderer/Tables/CellEditModalController.swift`

In `EditorContainer.swift`:
- Coordinator no longer holds `tableLayoutDelegate`, `cellSelectionDataSource`, `cellEditController`, `cellEditModalController`.
- `updateTableReveal`, `revealRow`, `adjustParagraphStyles`, `findTableRange`, `textRange` helper — all deleted (TK2-only).
- `renderCurrentText`'s `setAttributes` loop replaced with `setAttributedString`.
- `renderCurrentText`'s post-render `tlm.ensureLayout(...)` call retired (TK2 lazy-layout fix; TK1 doesn't need it).
- `renderCurrentText`'s scrollY save+restore (D15 origin) retired.
- `wireDocumentSubscription`'s sink no longer manually patches `textView.string` or chains a re-render — Combine flow goes through `renderCurrentText` only on external source changes.
- Initial seed no longer sets `textView.string = document.source`; the renderer produces the rendered form.

In `LiveRenderTextView.swift`:
- `cellEditController`, `cellEditModalController` weak vars deleted.
- `onDoubleClickRevealRequest` callback deleted.
- `mouseDown` collapsed to default + debug-probe recording.
- `scrollSuppressionDepth` + `scrollRangeToVisible` override + `isNavigationKey` helper + the `keyDown` suppression wrap all retired (phase 5).
- `currentTableRow`, `handleTab`, `handleLeftArrow`, `handleRightArrow`, `deleteBackward`, `deleteForward`, `sourceRange/nextTableRow/previousTableRow`, `TableRowInfo` struct, `menu(for:)` override, `editCellInPopoutAction`, `CellMenuTarget` — all deleted.
- New on TK1 (phase 6): `advanceCellOnTab(backward:)` + `cellTableInfo(at:in:)` for cell-aware Tab nav using `paragraphStyle.textBlocks`.

In `MarkdownRenderer.swift`:
- `visitTable` (and its helpers `renderCells`, `clampedLineRange`, `cellContent`) deleted. Tables are emitted by `TK1TableBuilder` during `buildAttributedString`'s replacement step.

In `HarnessCommandPoller.swift`:
- 12 actions deleted (overlay-/modal-/cell-table inspection actions). Five hundred-plus lines of action implementations gone.
- `cellEditController`, `cellEditModalController` weak refs deleted.
- `dump_state` no longer surfaces `overlay`, `modal`, `tables` sections (the layout shape they reflected doesn't exist).

In `LineNumberRulerView.swift`:
- `enumerateTextLayoutFragments` (TK2) replaced with iteration over `cachedLineStarts` + `lineFragmentRect(forGlyphAt:effectiveRange:)` (TK1).

---

## Files added

- `Sources/Editor/Renderer/Tables/TK1TableBuilder.swift` — markdown table → TK1 cell-paragraph attributed string.
- `Sources/Editor/Renderer/Tables/TK1Serializer.swift` — TK1 cell-paragraph attributed string → markdown source.

That's it. Two files, both small and focused.

---

## Foundation-doc updates

- `docs/stack-alternatives.md` — Axis 2 "Recommendation" flipped from TextKit 2 to TextKit 1, with the pivot rationale and the TextEdit / WWDC22 / Krzyżanowski citations from D16.
- `docs/engineering-standards_ref.md` § 2.2 inverted: was "never touch `.layoutManager`"; now "the text view is on TK1; `.layoutManager` IS the path; do not opt back into TK2." Change-log entry added.
- `docs/roadmap_ref.md` — D8/D8.1/D12/D13 marked "shipped … superseded by D17"; D16 GREEN; D17 ✅ Complete.

---

## Deferrals (D17 spec § 5 resolutions)

| Subsystem | Resolution | Note |
|---|---|---|
| D8.1 source-reveal mode | DROP | The mechanism survives in `git log` if anyone wants to revisit; in-place TK1 cell editing replaces it. |
| D13 modal popout | DROP | Brings back if dogfooding asks. |
| Active-cell border (Numbers-style) | DEFER to D18+ | Visual polish; not migration-blocking. |
| Cell-aware Tab nav | INCLUDE | Implemented in phase 6 against TK1 attribute model. |

---

## What survived from earlier work

- D9 reveal-at-line — unchanged (`scrollRangeToVisible` API is the same).
- D10 line numbers — ruler view ported to TK1 API; visual behavior identical.
- D11 CLI view-state flags — independent of text engine.
- D14 save / save as — independent.
- D15.1 debug HUD — survived; click-recorder rewritten against TK1 APIs (`glyphIndex(for:)`, paragraphStyle.textBlocks for cell detection).
- D15.1 harness regression scaffolding — tests stripped of TK2-specific assertions; pattern (file-based command poller, snapshot via `cacheDisplay`) carries forward.

---

## Verification

End-to-end across all phases:
- `docs/vision.md` (no tables) — renders correctly with line numbers, headings, bold/italic.
- `docs/roadmap_ref.md` (one table, ~13k chars) — table renders as native TK1 grid with column borders, header bolding, wrapped descriptions stack visual lines inside cells. Scroll into table from top: clean. Scroll deep past the table: clean. No blank gaps, no lazy-layout artifacts.
- Type a character mid-cell ("spike" → "spiXke") — storage updates, source serializes correctly, save writes markdown form with pipes intact.
- Tab from D# cell → Deliverable cell of same row (offset 560 → 563); Shift+Tab back (563 → 560). Stock NSTextView click resolution lands the caret in the right cell.
- `grep -rn 'NSTextLayoutFragment\|NSTextLayoutManager\|TableRowFragment\|TableLayoutManagerDelegate\|TableRowAttachment\|CellEditOverlay\|CellEditController\|CellEditModalController\|CellSelectionDataSource\|TableLayout\b' Sources/` returns four hits, all in doc comments explaining what was retired. No live code references.

Manual test plan: `docs/current_work/testing/d17_textkit1_migration_manual_test_plan.md`.

---

## Known carryover for future work

1. **Single-tab Tab nav across multiple tables** — Tab past the last cell of one table doesn't enter the next table. Falls through to default (which inserts a tab character). Acceptable for now; if it becomes a workflow request, advance from "no next cell in this table" to "first cell of next table down" in `advanceCellOnTab`.
2. **Active-cell border** — deferred to D18+. The TK1 path doesn't render a visual focus indicator for the active cell; users see the standard caret. Numbers/Excel-style border is purely cosmetic.
3. **Modal popout** — dropped per spec. If dogfooding wants long-form cell editing in a separate window, revisit.
4. **Source-reveal mode (D8.1)** — dropped per spec. Cell editing is in-place; users don't need a "show the markdown for this table" toggle. Power users can fall through to a different editor for that.
5. **Selection-preservation across full re-render** — best-effort only. If an external edit fires a re-render, the user's caret position is clamped to new storage length. For most cases this is fine; for edits that change the doc significantly (e.g., a rename in a synced collaboration scenario) the caret may land somewhere unexpected.
6. **Performance for large docs** — `TK1Serializer.serialize` runs on every keystroke. For docs in the 10–25k char range we tested, this is fast enough. For >100k chars it may need an incremental-update optimization (track which paragraph was edited, splice into source rather than re-serialize).
7. **Round-trip whitespace normalization** — the serializer emits canonical `| cell |` formatting; if the original markdown had `|cell|` (no spaces) or `|  cell  |` (extra spaces), save normalizes to one space. Visual content unchanged; bytes-on-disk changed.

---

## End of TK1 migration

The pivot from TK2 to TK1 cost two days end-to-end (D15.1 partial + D16 spike + D17 migration). It deleted ~3,200 lines of code and resolved a recurring class of bugs in the platform's table layout. The architecture is now aligned with how Apple's own apps handle tables. The codebase is smaller, simpler, and the parts that were fragile (custom fragment heights, lazy-layout coordination, scroll suppression workarounds, cell-edit overlay machinery) are gone.
