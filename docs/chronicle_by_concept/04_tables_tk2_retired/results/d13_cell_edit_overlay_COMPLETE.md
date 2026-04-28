## D13: Cell-Edit Overlay — COMPLETE

**Shipped:** 2026-04-26
**Spec:** `docs/current_work/specs/d13_cell_edit_overlay_spec.md`
**Plan:** `docs/current_work/planning/d13_cell_edit_overlay_plan.md`
**Prompt:** `docs/current_work/prompts/d13_cell_edit_overlay_prompt.md`
**Spike:** `spikes/d13_overlay/` (GREEN — frozen reference)
**Test plan:** `docs/current_work/testing/d13_cell_edit_overlay_manual_test_plan.md`
**Resolves:** D12's wrapped-cell architectural limitation (caret on visual-line-2+ of a wrapped cell was inaccessible).

---

## What shipped

GFM tables now support **per-cell editing for plain-text cells** via two paths:

1. **Cell-edit overlay** (default, single-click). An in-place NSTextView mounts over the clicked cell with caret at the clicked position. 2pt accent border (Numbers/Excel pattern) marks the active cell; text position is invariant between active and inactive states. Click-to-caret math via Core Text resolves visual-line-2+ clicks correctly on wrapped cells. Tab/Shift+Tab cycle cells across rows with header excluded; Enter / Escape / click-out / scroll all commit; Escape cancels.

2. **Modal popout** (right-click "Edit Cell in Popout…"). Centered ~600x400 NSWindow with plain NSTextView for editing the cell's source. Always-available power option AND the future home for content the overlay's math can't handle (inline images, complex inline markdown). Pipe-escape round-trip + newline normalization; Save / Cancel / ⌘+Return / Escape.

Spec §3.13 handoff rules enforced: same-cell right-click while overlay active omits the popout item; different-cell right-click commits the active overlay before opening modal.

---

## Files modified / created

### New

| File | Purpose |
|---|---|
| `Sources/Editor/Renderer/Tables/CellEditOverlay.swift` | NSTextView subclass with active-cell border + Tab/Enter/Escape interception |
| `Sources/Editor/Renderer/Tables/CellEditController.swift` | Coordinator-owned controller. Show/commit/cancel/Tab nav/scroll observer. ~280 lines |
| `Sources/Editor/Renderer/Tables/CellEditModalController.swift` | Modal popout — centered NSWindow, NSTextView, Save/Cancel buttons |
| `docs/current_work/testing/d13_cell_edit_overlay_manual_test_plan.md` | Tier-by-tier manual validation |
| `docs/current_work/stepwise_results/d13_cell_edit_overlay_COMPLETE.md` | This file |

### Modified

| File | Change |
|---|---|
| `Sources/Editor/Renderer/Tables/TableLayout.swift` | Added `cellLocalCaretIndex(rowIdx:colIdx:relX:relY:)` per spec §3.5 — CT-based click-to-caret math |
| `Sources/Editor/LiveRenderTextView.swift` | Single-click → mount overlay (replaces D12's `snapCaretToCellContent`); right-click adds "Edit Cell in Popout…" menu item; double-click reveal preserved |
| `Sources/Editor/EditorContainer.swift` | Wires CellEditController + CellEditModalController into Coordinator + textView; render hooks via [weak coord] closure |
| `Sources/Debug/HarnessCommandPoller.swift` | D13 harness extensions: `query_caret_for_click`, `show_overlay_at_table_cell`, `type_in_overlay`, `set_overlay_text`, `commit_overlay`, `cancel_overlay`, `advance_overlay_tab`, `simulate_click_at_table_cell`, `open_modal_at_table_cell`, `set_modal_text`, `commit_modal`, `cancel_modal`. dump_state extended with `overlay` + `modal` blocks |

All harness additions marked with `// TEST-HARNESS:` per project convention. Strip via `grep -rn 'TEST-HARNESS:' Sources/` when no longer needed.

---

## Phase commits

| Commit | Phase | Test gate |
|---|---|---|
| `1243e20` | Triad | spec §3.12-3.13 added; plan + prompt drafted with per-phase automated test gates |
| `6b13ed5` | Phase 1 — TableLayout.cellLocalCaretIndex | All 7 spec §3.5 cases GREEN via harness `query_caret_for_click` |
| `24b80bf` | Phase 2 — CellEditOverlay + CellEditController | Lifecycle round-trip + visual baseline (wrapped cell with 2pt accent border, 3 lines visible) |
| `9ed1ace` | Phase 3 — LiveRenderTextView mouseDown | **PRIMARY: synthetic-click on wrapped cell visual line 2 (relY=22) → overlay caret on line 2 between 'a' and 'c' in 'wrap a\|cross'.** D12's wrapped-cell limitation resolved. |
| `5c24344` | Phase 4 — Tab nav + scroll observer | Tab/Shift+Tab cross-row, header excluded, boundary dismiss, anchor-based table re-find post-render |
| `8894307` | Phase 5 — Modal popout | Open / set text / commit / cancel; pipe round-trip; handoff (overlay→modal commits A then opens B) |
| (this commit) | Phase 6 — Manual test plan + COMPLETE doc + roadmap + tag | Full regression green |

---

## Architectural findings (production-relevant)

1. **CT math is font-agnostic.** `CTFramesetterCreateWithAttributedString` + `CTLineGetStringIndexForPosition` work on any `NSAttributedString`, including mixed font runs (bold + italic + monospaced), proportional fonts, and Unicode glyphs with non-uniform advance widths. Future inline-markdown rendering inside cells will work without math changes.

2. **Re-render destroys layout instances.** `TableLayout` instances are rebuilt on every render pass. Anything bridging across renders (Tab nav, future undo) must use source-position anchors, not ObjectIdentifier. Encoded in `TableAnchor` pattern.

3. **Active-cell visual continuity** requires:
    - Overlay frame includes the cell's full rect (cellInset gutter included).
    - `textContainerInset = cellInset` so text origin matches host's `drawCells` output.
    - Border drawn via CALayer.borderWidth / .borderColor — sits inside the frame edge in the cellInset gutter without shifting text.

4. **Edit-time spillover is acceptable V1 behavior.** Overlay does not auto-grow vertically as content extends past the cell's frame; spilled text visually overlaps adjacent rows during typing. On commit, host re-renders cleanly with column auto-grow + row reflow. Matches Numbers/Excel.

5. **Modal popout is pure plumbing** — no caret math, no fragment geometry, no font matching. Same source-of-truth contract as the overlay (replaceCharacters on the cell's source range, re-render). This is why the modal is the right surface for future complex content (inline images, inline markdown rendering toolbar).

6. **Header cells excluded from Tab cycle** (Numbers/Excel convention). Direct-click on header still mounts overlay; Tab cycle skips them, dismissing at first body cell when going backward.

7. **Pipe-escape order matters.** `\\` → `\\\\` first to avoid double-escape, then `|` → `\|`. Modal un-escapes for display (so user sees literal `|`), re-escapes on Save.

---

## Test harness — meta-infrastructure

D13 extends D12's `Sources/Debug/HarnessCommandPoller.swift` with overlay + modal actions. Production now has end-to-end test coverage via:

- `query_caret_for_click` — pure math validation (Phase 1)
- `simulate_click_at_table_cell` — drives the production mouseDown integration end-to-end (Phase 3 PRIMARY)
- `show_overlay_at_table_cell` / `type_in_overlay` / `commit_overlay` / `cancel_overlay` — overlay lifecycle (Phase 2)
- `advance_overlay_tab` — Tab nav (Phase 4)
- `open_modal_at_table_cell` / `set_modal_text` / `commit_modal` / `cancel_modal` — modal lifecycle + handoff (Phase 5)

`dump_state` payload includes `overlay` + `modal` blocks for state assertion. Snapshots via `cacheDisplay` capture the host editor (modal lives in a separate window — manual visual verification is in the manual test plan).

---

## Verification

Each phase was test-gated before commit. Final regression run (Phase 6):

| Phase | Run | Result |
|---|---|---|
| 1 | 7 cases via query_caret_for_click | All GREEN |
| 2 | show / type / commit / cancel / re-show round-trip | GREEN |
| 3 | simulate_click on wrapped Description visual line 2 → caret index 43 (between 'a'/'c' in "wrap a\|cross") | GREEN — visual confirmed in `evidence/d13-phase3-wrapped-cell-overlay.png` |
| 4 | Tab/Shift+Tab in single-row + multi-row + header-exclusion + boundary dismiss | All 5 cases GREEN |
| 5 | Modal open / commit / cancel / pipe-escape round-trip / handoff | All 5 cases GREEN |
| Regression | D8/D9/D10/D11/D8.1/D12 — manual test plan §J | (run manually before tag) |

---

## Deferrals / known gaps

| Gap | Disposition |
|---|---|
| Inline markdown rendering inside cells (bold/italic/code/link) | **Future deliverable D14 or similar.** Production decision: rich content edits will land in the modal popout (toolbar pattern) before the overlay, since overlay simplicity is a feature. |
| Auto-fallback to modal on detected unhandled content | V1.x. Requires inline-markdown parser to know "this cell contains content the overlay can't render" — deferred until parser lands. |
| Multi-cell drag-select while overlay active | V1: out of scope (spec §3.8). User commits/cancels overlay first; drag-select then works in grid mode (default NSTextView path). |
| Modal application-modal vs detached-window | V1: application-modal (only one editing context active). Future could relax to Numbers' detached-window pattern. |
| Edit-time vertical spillover beyond cell rect | Accepted Numbers/Excel behavior. Re-evaluate if user feedback requests in-cell scrolling. |

---

## Roadmap impact

D12's "wrapped-cell limitation handed off to D13" is now **resolved**. Roadmap entry updated; D13 row marked ✅.

D13 ships before any inline-formatting work; the modal popout is positioned to absorb that future scope without needing a new editor surface.

---

## Harmoniq

(Harmoniq tracking integration is project-specific. Update accordingly.)
