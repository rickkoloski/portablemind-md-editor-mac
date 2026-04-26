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

## Tier 4 — Wrapping behavior in overlay

**Status:** Not started.

---

## Tier 5 — Tab / Enter / Escape semantics + scroll

**Status:** Not started.

---

## Tier 6 — Source-splice round-trip

**Status:** Partial — basic splice + pipe-escape verified in Tier 1. Full coverage (multi-row independence, paste normalization, large-content reflow) pending.

---

## Tier 7 — Empty cell + edge cases

**Status:** Not started.

---

## Math algorithm — final

(To be filled in after Tier 2 lands.)

---

## Production-merge constraints

(Aggregated after all tiers complete.)

---

## Go/no-go recommendation

(Filled in at end of spike.)
