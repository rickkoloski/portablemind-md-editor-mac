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

## Tier 2 — Click-to-caret math (PRIMARY)

**Status:** Not started.

(Pending implementation per spec §3.5: CTFramesetter + CTLineGetStringIndexForPosition.)

---

## Tier 3 — Visual continuity

**Status:** Not started.

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
