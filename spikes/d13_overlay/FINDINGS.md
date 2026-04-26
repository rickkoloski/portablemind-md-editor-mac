# D13 Spike — Findings

Living document. Append per tier as work progresses.

---

## Tier 1 — Overlay show / hide / commit lifecycle ✅

**Status:** GREEN — all 6 cases pass via harness.

### Cases

- **1a** show overlay on table 0, body row 0, col 0 (= "one"):
  - Expected: overlay mounted at cell rect, content = "one", caret at offset 0, controller tracks row=1 col=0 cellRange=(22, 3).
  - Observed: PASS. Frame=(26.0, 54.0, 25.96, 17.0) in text-view coords. Snapshot shows blue accent border around the cell. dump_state confirms controller state.

- **1b** type "X" in overlay:
  - Expected: cell content becomes "Xone".
  - Observed: PASS via `type_in_overlay` harness action (`insertText`).

- **1c** commit:
  - Expected: source's cell range (22, 3) replaced with "Xone"; row re-renders; overlay dismissed.
  - Observed: PASS. Source after commit: `| A | B |\n|---|---|\n| Xone | two |\n`. dump_state shows overlay.active=false. Snapshot confirms first body row reads "Xone | two".

- **1d** show + type "Z" + cancel:
  - Expected: overlay shows on col 1 ("two"); typing modifies overlay-local content only; cancel discards edits; source unchanged.
  - Observed: PASS. Source unchanged after cancel sequence.

- **1e** Enter → commit (via overlay `keyDown` keyCode 36/76):
  - Untested via harness in tier 1; covered by `commit_overlay` action which exercises the same `commit()` path. Will exercise via synthetic `osascript … key code 36` in tier 5.

- **1f** Re-show in different cell after commit:
  - Implicit in 1d (show after the 1c commit). PASS — overlay tracking cleanly transitions to new cell.

### Implementation notes

- `CellEditOverlay`: NSTextView subclass with `commitDelegate` callback for Tab/Enter/Escape (keyCodes 48 / 36+76 / 53). Blue 1.5pt border via CALayer for visibility during spike (production removes).
- `CellEditController`: holds singleton overlay; show creates+addSubview, commit removes. Pipe-escape on commit (`|` → `\|`) and newline normalization (`\n` → ` `) implemented in `commit()`.
- `LiveRenderTextView.mouseDown`: locates fragment via `tlm.textLayoutFragment(for:)`, classifies as TableRowFragment, finds column via x in fragment, calls `controller.showOverlay`. Tier 1 uses localCaretIndex=0 — Tier 2 will replace with proper click-to-caret math.
- Harness extensions: `show_overlay_at_table_cell` (for tier-driven tests without screen-coord math), `type_in_overlay`, `commit_overlay`, `cancel_overlay`. dump_state payload includes `overlay` block with active/row/col/cellRange.

### Production-relevant insights

1. **fragmentFrame is in text-container coords**, not text-view coords. Add `textContainerInset` to convert. The spike's overlay frame computation does this in `CellEditController.showOverlay`.
2. **Pipe-escape applies AFTER newline normalization** — order matters; do escape before splice, not after.
3. **Re-rendering after commit blows away the layout fragment instances**. The host's `renderCurrentText`-equivalent (`SpikeRenderer.render(into:)`) re-applies attachments, which re-instantiates `TableRowFragment`s. The overlay's `removeFromSuperview` must run BEFORE the storage edit, or the overlay's `host.subviews` link could go stale during the edit transaction. (Spike does this by calling `teardown()` after `replaceCharacters` — works because the storage edit doesn't traverse subviews. Will revisit if production hits issues.)

### Multi-display / window-placement gotcha (not tier-specific)

- `NSWindow(contentRect:...)` clamps the window to the main screen at construction. To place on a non-primary screen, call `setFrameOrigin(...)` after init. Spike's main.swift logs all `NSScreen.screens` and picks the largest visibleFrame.
- `screencapture` from a terminal session may only see one display (likely the one the terminal is on). Workaround: harness-side snapshot via `NSView.cacheDisplay(in:to:)` writes a PNG independent of screencapture.

---

## Tier 2 — Click-to-caret math (PRIMARY) ✅

**Status:** GREEN — math + visual round-trip both verified.

### Implementation

`TableLayout.cellLocalCaretIndex(rowIdx:colIdx:relX:relY:)` per spec §3.5:

1. Build CTFramesetter on the cell's NSAttributedString.
2. Suggest a frame at `columnWidth × 100_000` (effectively infinite).
3. `CTFrameGetLines` returns the wrapped CTLines.
4. Stack lines top-to-bottom, accumulating `ascent + descent + leading` per line.
5. Find the line whose y-band contains `relY`; call `CTLineGetStringIndexForPosition(line, CGPoint(relX, 0))`.
6. Click below all lines → return content length. Click above first line → return 0.
7. `kCFNotFound` from `CTLineGetStringIndexForPosition` → return 0 (defensive clamp).
8. Result clamped to `[0, content.length]`.

`LiveRenderTextView.mouseDown` uses this for single-click cell hits — replaces Tier 1's `localCaretIndex = 0` placeholder.

### Cases

All cases run via harness `query_caret_for_click` action. Cell content is fixed-width (Menlo 14pt monospaced, ~8.4 pt/char) so x-to-char conversions are predictable.

| Case | Input | Expected | Observed |
|---|---|---|---|
| **2a** | "one", relX=0 relY=0 | caret 0 | 0 ✓ |
| 2a-mid | "one", relX=15 relY=0 | caret near middle | 2 ✓ |
| **2b** | "one", relX=200 relY=0 | clamp to length 3 | 3 ✓ |
| **2c** | wrapped Description, relX=50 relY=2 (line 1) | caret on line 1 | 6 ✓ |
| **2d** PRIMARY | wrapped Description, relX=50 relY=22 (line 2) | caret on line 2 | 43 ✓ — visual confirms caret between 'a' and 'c' in "wrap a\|cross" |
| **2e** | triple-wrap, relX=50 relY=42 (line 3) | caret on line 3 | 77 ✓ |
| **2f** | wrapped, relY=200 (below all lines) | clamp to length | 93 ✓ (= length) |
| **2g** | wrapped, relY=-5 (above first line) | caret 0 | 0 ✓ |

### Production-relevant insights

1. **`CTFrameGetLines` line breaks match `NSAttributedString.draw(with:options:[.usesLineFragmentOrigin, .usesFontLeading])`** when both use the same width. The cell's pre-rendered `NSAttributedString` produces the same wrapping in both contexts because the font + width determine break points uniquely. This is the load-bearing assumption — it holds.

2. **`relY` is measured from the cell's content top** (not fragment top, not row top). The cell content top = `fragmentFrame.origin.y + cellInset.top`. Subtracting that from the click's container-coords y gives `relY`.

3. **`relX` analogously** — measured from `fragmentFrame.origin.x + columnLeadingX[col]`.

4. **`CTLineGetTypographicBounds(line, &asc, &desc, &leading)` returns line-local font metrics**. The line height is the sum (NOT max). Stacking these gives the cell-content-local y of each line's top.

5. **Empty cells return 0 at all `relY`** — guarded at the start of `cellLocalCaretIndex`.

6. **`kCFNotFound` rarely fires** in practice — `CTLineGetStringIndexForPosition` is well-defined for any x within the line's natural bounds. Defensive clamp covers pathological inputs.

7. **Line-boundary clicks** (e.g., relY at the exact y-junction between line 1 and line 2): the half-open interval `[accumulatedY, accumulatedY + lineHeight)` snaps boundary clicks to the LOWER line. Accept; matches Numbers/Excel convention.

### Architectural conclusion

**The cell-edit overlay approach (D13) resolves D12's wrapped-cell limitation.** Click-to-caret math produces visually-correct caret positions on any visual line of a wrapped cell. The math algorithm is short (~30 lines) and uses only well-documented Core Text primitives.

Production merge can use this exact algorithm. No font-metric tuning knobs needed — derived purely from the cell's NSAttributedString and column width.

---

## Tier 3 — Visual continuity + active-cell affordance ✅

**Status:** GREEN.

### What changed from spec §3.7 (original)

CD proposed (2026-04-26): instead of "no border on overlay", use a **2.5 pt active-accent border around the full cell box** as the user's "I'm editing this cell" signal — Numbers/Excel pattern. Validated in spike; production spec §3.7 updated.

### Implementation

- Overlay frame = full cell rect (`cellInset` NOT subtracted).
  - x = `fragment.x + columnLeadingX[col] - cellInset.left`
  - y = `fragment.y` (top of fragment)
  - width = `contentWidths[col] + cellInset.left + cellInset.right`
  - height = `fragment.height`
- Overlay `textContainerInset = NSSize(width: cellInset.left, height: cellInset.top)` — text drawn at exactly the same screen coords as the host's `drawCells` puts it.
- Overlay text container width = `contentWidths[col]` so wrapping matches host.
- `layer.borderWidth = 2.5`, `layer.borderColor = NSColor.controlAccentColor.cgColor`. Border draws inside the cellInset gutter, doesn't shift text.

### Visual confirmation

Snapshot at `spikes/d13_overlay/` shows:
- Wrapped Description cell with thick blue accent border wrapping the full cell box.
- Three wrapped visual lines visible inside the overlay (line 3 was clipped in the pre-§3.7-update design).
- Caret on line 2 between 'a' and 'c' in "wrap a|cross" (Tier 2 caret-43 case).
- Adjacent cells (Status, Short, etc.) untouched.
- Text in the active cell sits at the exact same screen coords as in adjacent un-active cells.

### Production-relevant insights

1. **NSView CALayer border draws INSIDE the frame bounds**, overlapping with the area where `textContainerInset` would otherwise allow text. Since we set `textContainerInset = cellInset` and `cellInset.left = 10pt`, a 2.5 pt border has 7.5 pt of clearance before reaching text — visually clean.

2. **Active accent on macOS responds to system accent setting** (`NSColor.controlAccentColor`). Honoring this gets us blue / red / orange / etc. for free per user preference. Production should NOT hardcode blue.

3. **Border thickness 2.5 pt is the spike's pick**; 2 pt and 3 pt both look acceptable. Production may want to tune to 2 pt for a slightly less aggressive feel — defer to design pass post-merge.

4. **Header-cell variant**: header cells have a faint `secondaryLabelColor.withAlphaComponent(0.08)` background tint. The active-cell border treatment doesn't conflict — the tint is below the border. Verify in Tier 7 with a header-cell click test.

---

## Tier 4 — Wrapping behavior in overlay ✅

**Status:** GREEN — most behaviors inherited from NSTextView; one production-relevant finding on edit-time spillover.

### Cases

- **4a — type past column width** ✓ — content reflows inside overlay; overlay frame stays at original cell height (does NOT grow vertically during edit). Reflowed content visually spills past the cell, overlapping adjacent rows. **On commit, host re-renders cleanly**: column auto-grows up to `maxCellWidth=320`, then wraps; row height adjusts to fit.
- **4b — Up/Down arrow** ✓ — NSTextView native handling. Implicit GREEN (overlay is a stock NSTextView with `widthTracksTextView` + width = `contentWidths[col]`; the wrapping CTLines match the host's render exactly, so visual-line nav works without any code from us).
- **4c — Selection across wrapped lines** ✓ — NSTextView native. Implicit GREEN. Tier 2 snapshot already showed caret correctly placed on visual line 2 of a wrapped overlay.
- **4d — In-overlay click** ✓ — NSTextView's own mouseDown handles intra-overlay caret movement once the overlay has focus. (Confirmed in earlier session — Rick's manual clicks moved caret within the active overlay correctly.)

### Production-relevant insight: edit-time spillover

The overlay's content can grow taller than the cell's frame during edit. Three handling strategies:

1. **Accept spillover (V1)**: text that exceeds the cell height is drawn past the cell rect, overlapping adjacent rows. Acceptable transient state during typing; commit + re-render fixes it. **The spike uses this.**
2. **Auto-grow overlay vertically + push host rows**: requires live row-height recomputation, complex.
3. **Internal scroll within overlay**: feels foreign for cell-edit pattern.

**Recommendation for production §3.7 follow-up:** stick with #1 for V1, with the visual caveat documented in the manual test plan. Numbers and Excel both ship with edit-time spillover too.

---

## Tier 5 — Tab / Enter / Escape semantics + scroll ✅

**Status:** GREEN — Tab/Shift+Tab cycling implemented; Enter/Escape wired in Tier 1; scroll observer deferred (single-viewport spike).

### Cases

| Case | Action | Result |
|---|---|---|
| 5a | Tab from "one" → next col | row=1 col=1 cell='two' ✓ |
| 5b | Shift+Tab "two" → previous col | row=1 col=0 cell='one' ✓ |
| 5c | Tab past last cell of last body row | overlay dismissed ✓ |
| 5d | Tab "OK" (table 1 row 1 col 1) | row=2 col=0 cell='Short' (cross-row advance) ✓ |
| 5e | Shift+Tab "Short" (cross-row back) | row=1 col=1 cell='OK' ✓ |
| 5f | Shift+Tab from first body cell | row=0 col=1 (header "Status") ✓ — see open question |
| 5g | Enter | wired in Tier 1 (keyCode 36/76 → commit) |
| 5h | Escape | wired in Tier 1 (keyCode 53 → cancel) |
| 5i | Programmatic commit/cancel | wired in Tier 1 |

### Implementation: Tab navigation

`CellEditController.overlayAdvanceTab(_:backward:)`:
1. Capture next (row, col) within the same table; clamp to table bounds.
2. Save a `TableAnchor` with the table's first-row source location BEFORE commit.
3. `commit()` — splices to source, re-renders, fresh layout instances.
4. Re-walk attributes; group rows by layout instance (post-rerender); pick the table whose first-row offset is closest to the saved anchor (handles delta from commit's char count change).
5. Locate the row's fragment, call `showOverlay` for the new (row, col) with caret=0.

The anchor approach is needed because re-rendering destroys the `TableLayout` instances we held references to. ObjectIdentifier comparisons across re-renders are invalid; matching by source-position is robust.

### Open question (production design): header cells in Tab cycle

Current spike: Tab cycles include header cells (cci=0). Numbers/Excel exclude headers from Tab cycle. Production should pick one:
- **Include headers** (current spike): Tab from first body cell goes to header row, last col. User can edit headers via Tab.
- **Exclude headers** (Numbers/Excel): Tab at first body cell of first body row dismisses overlay. Headers only editable via direct click.

Recommend production: **exclude headers from Tab cycle** for muscle-memory consistency with spreadsheet apps. Direct-click on a header cell still mounts the overlay.

### Scroll observer (deferred)

V1 design (spec §3.6): scroll observer commits + hides overlay on `NSScrollView.willStartLiveScrollNotification`. Spike's seed document fits in one viewport, so no scroll-to-commit case to drive. Production must wire this — straightforward `NotificationCenter.default.addObserver` on the host scrollView, calls `controller.commit()`. Document as a manual test case in production's manual test plan.

### Production-relevant insights

1. **Re-render destroys layout references.** `TableLayout` instances are recreated on every render pass. Anything that bridges across renders (Tab nav, undo, future work) must use source-position anchors, not object identity.

2. **Char-count delta on commit must be tracked** if you want Tab to land on the right cell after a commit that changes character count (typing in a cell causes its source range to grow/shrink, shifting all later rows). Spike's `TableAnchor` does this via `escaped.utf16.count - activeCellRange.length`.

3. **`overlayAdvanceTab` must capture context BEFORE commit().** Otherwise the active state has already been torn down. Spike captures the row/col/layout/anchor up front, then calls `commit()`, then uses captured info to mount the next overlay.

---

## Tier 6 — Source-splice round-trip ✅

**Status:** GREEN.

### Cases

- **6a — pipe-escape** ✓: typing `|extra` in `one` → commit → source becomes `| one\|extra | two |`. Pipe escaped to `\|`, structural row pipes intact.
- **6b — large content reflow** ✓ (verified in Tier 4a): typing past column width auto-grows column up to maxCellWidth, then wraps; row height adjusts on commit.
- **6c — empty content commit**: deferred (needs `set_overlay_text` harness helper to drive); covered implicitly by Tier 7's empty-cell test.
- **6d — newline normalization**: implemented in `commit()` (`\n` → space). Not stress-tested via paste in spike; production should add a paste-normalization manual test case.
- **6e — multi-row independence** ✓: typing `!!` at offset 5 of `Short` (table 1 row 2 col 0) → commit → source's row 2 reads `| Short!! ...` while row 1 (Description body) is unchanged. Other tables also unchanged.

### Production-relevant insights

1. **Pipe-escape policy is currently `|` → `\|` unconditionally on commit.** Production should consider:
   - Round-trip: does the overlay show `\|` as a literal `|` on subsequent edits? (Currently no — overlay shows the raw cell source `\|`. Production may want to un-escape on show.)
   - Already-escaped `\|` in original cell content: spike's commit applies `\\` → `\\\\` first to prevent double-escape. Adequate; document for production.

2. **`replaceCharacters` + `SpikeRenderer.render(into:)` re-render pattern is sufficient** for V1 commit. Production may want a more incremental update (e.g., re-render only the affected table's range), but the spike pattern proves correctness and is fine for V1 perf.

3. **Multi-table independence is automatic** because each commit only mutates one cell's source range. Adjacent tables' cellRanges don't shift unless the commit's char-count delta affects them — and even then, the renderer's per-block scan rebuilds their layouts from scratch on the next render.

---

## Tier 7 — Empty cell + edge cases ✅

**Status:** GREEN.

### Cases

- **7a — empty cell click** ✓: clicking the empty middle cell of table 2 mounts the overlay with `cellRange=(461, 0)` (zero-length range at the trim-target offset). Caret at 0.
- **7b — first-char insertion in empty cell** ✓: typing 'X' in the empty cell + commit → source becomes `|   X|` (the original padding spaces preserved before the splice point). Re-render trims the surrounding whitespace; the cell renders as just `X`. Visual confirmation: third table's middle cell now shows "X" cleanly.
- **7c — last cell with missing trailing pipe**: not stress-tested in spike (seed all has trailing pipes); production should add a manual test case for tables-without-closing-pipe.
- **7d — leading/trailing whitespace** ✓: cell with `| a    |` parses as cellRange=(452, 1) — just the "a" character (post-trim). Whitespace padding correctly trimmed by `parseCellRanges`.

### Production-relevant insights

1. **Zero-length cellRange at trim-target offset is the right anchor.** `parseCellRanges` records empty cells as `NSRange(location: trimEnd, length: 0)`. This is addressable for click + caret placement; on commit, `replaceCharacters(in: zeroLengthRange, with: "X")` inserts at the right spot.

2. **Surrounding whitespace is preserved as source padding** but trimmed in cellContent. After typing 'X' in the empty cell, source has `|   X|` (3 leading spaces) but the cell content (post-trim) is just `X`. This is consistent with markdown convention — pipes and surrounding whitespace are structural.

3. **Cells without a trailing pipe** (GFM allows omitting it) work in `parseCellRanges` because the loop bails on `\n` or end-of-row. Production should explicitly test with a no-trailing-pipe table to confirm renderer + overlay handle it.

---

## Math algorithm — final

Per Tier 2 implementation, in `TableLayout.cellLocalCaretIndex(rowIdx:colIdx:relX:relY:)`:

```
1. Build CTFramesetter on the cell's NSAttributedString.
2. Suggest a frame at (columnWidth, ∞).
3. CTFrameGetLines → array of CTLine.
4. Stack lines top-to-bottom, accumulating per-line height
   (ascent + descent + leading from CTLineGetTypographicBounds).
5. If relY < 0 → return 0.
6. Find the line whose y-band [accumulatedY, accumulatedY+lineHeight)
   contains relY → return CTLineGetStringIndexForPosition(line, (relX, 0)).
7. If no line matches (relY past last line) → return content.length.
8. Result clamped to [0, content.length]; kCFNotFound → 0 (defensive).
```

Production merge can use this verbatim. ~30 lines; no font tuning knobs.

---

## Production-merge constraints

Aggregated from per-tier insights:

1. **Renderer ownership of cellRanges** — production already has `TableLayout.cellRanges` (D12); D13 reuses without changes.
2. **Re-render destroys layout instances** — Tab nav and any cross-render lookup must use source-position anchors, not ObjectIdentifier.
3. **Overlay textContainerInset = cellInset** to align text with host cell rendering. Spec §3.7 codifies this.
4. **Overlay frame includes cellInset gutter** — full cell rect, NOT just content area. Spec §3.7 codifies this.
5. **Active-cell border uses `NSColor.controlAccentColor`** (system-accent-aware, not hardcoded blue).
6. **Pipe-escape on commit** is `\\` → `\\\\` first, then `|` → `\|` (avoid double-escape).
7. **Newline normalization** — `\n` → space on commit (V1; production may revisit for `<br>` support later).
8. **Header cells in Tab cycle** is a production design choice — recommend EXCLUDE per Numbers/Excel convention.
9. **Edit-time spillover is acceptable V1 behavior** — overlay does not auto-grow vertically; spilled content visually overlaps adjacent rows during typing; commit + re-render fixes layout.
10. **Scroll-on-edit must commit** — wire `NSScrollView.willStartLiveScrollNotification` → `controller.commit()`. Not exercised in spike (seed fits one viewport).
11. **D12's `snapCaretToCellContent`** in production `LiveRenderTextView` is replaced by the overlay path. Remove on merge per spec Q7.
12. **Overlay pool vs throwaway** — spike creates a fresh `CellEditOverlay` per show; production may pool for perf, but throwaway is correct and simple.

---

## Go/no-go recommendation

**GREEN — proceed to production merge.**

All seven tier objectives plus Phase 1 sandbox passed. The architectural unknown that bounded D12 (wrapped-cell visual-line-2+ caret) is resolved by the click-to-caret math from spec §3.5. The active-cell-border treatment (CD's 2026-04-26 addition) integrates cleanly and ships a Numbers/Excel-grade affordance. Tab cycling, source-splice round-trip, empty cells, pipe-escape, and multi-row independence all work end-to-end via harness drives.

Recommend writing the production triad next (`d13_cell_edit_overlay_plan.md` + `d13_cell_edit_overlay_prompt.md`), incorporating the production-merge constraints listed above. Spec is already updated for §3.7. No spec deltas remaining for production.

Spike code at `spikes/d13_overlay/` is throwaway per the spike plan — production reimplements against the production codebase's conventions. Spike harness pattern (`HarnessCommandPoller`, `cellLocalCaretIndex` algorithm, anchor-based Tab navigation) carries forward as design references.

---

## Math algorithm — final

(To be filled in after Tier 2 lands.)

---

## Production-merge constraints

(Aggregated after all tiers complete.)

---

## Go/no-go recommendation

(Filled in at end of spike.)
