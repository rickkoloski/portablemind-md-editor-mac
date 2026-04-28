# D12: Per-Cell Table Editing — CC Prompt

**Spec:** `docs/current_work/specs/d12_per_cell_table_editing_spec.md`
**Plan:** `docs/current_work/planning/d12_per_cell_table_editing_plan.md`

---

## Context

D8 rendered GFM tables as a visual grid via TextKit 2 custom fragment substitution. D8.1 added reveal-on-caret so typing inside a table dropped the whole table to pipe source. That reveal mechanism works mechanically but the UX is wrong:

- Single-click → whole-table source switch is jarring.
- Caret in source mode draws at the source character's horizontal position (often past the viewport) and at the grid-row height (tall, ruler-like).
- Vast majority of table edits are cell-scoped, not whole-table.

D12 replaces the primary path: **single-click places the caret inside a cell** with the grid staying rendered, at natural caret height and position. Typing updates the cell's source. D8.1's whole-table reveal is retained as a secondary path, triggered by **double-click** (or menu / keyboard shortcut) — same mechanism, different trigger, same caret-position/size bug fixed by removing the paragraph-style min/max-line-height forcing during reveal.

**Pre-users principle:** md-editor has no user base yet. Build the correct design, not a shortcut. No modal fallback is acceptable (see parked alternative in memory `md_editor_d12_break_glass_fallback.md` — explicitly out of scope for D12).

**Read before starting:**
- `docs/current_work/specs/d12_per_cell_table_editing_spec.md` (full behavior contract)
- `docs/current_work/planning/d12_per_cell_table_editing_plan.md` (Phase 1 spike + Phase 2 steps)
- `docs/current_work/stepwise_results/d08_1_table_reveal_COMPLETE.md` (current state of the reveal machinery you'll repurpose)
- `Sources/Editor/Renderer/Tables/TableRowFragment.swift`
- `Sources/Editor/Renderer/Tables/TableLayout.swift`
- `Sources/Editor/Renderer/Tables/TableLayoutManagerDelegate.swift`
- `Sources/Editor/Renderer/MarkdownRenderer.swift` — `visitTable`
- `Sources/Editor/EditorContainer.swift` — Coordinator (especially `updateTableReveal`)
- `Sources/Editor/LiveRenderTextView.swift`

---

## Task

Implement per-cell table editing per the spec + plan. Phase 1 first (spike), then Phase 2 production work.

### Phase 1 — Spike (REQUIRED BEFORE Phase 2)

Build a throwaway reproducer at `spikes/d12_cell_caret/` that validates whether `NSTextLayoutFragment.textLineFragments` can return per-cell line fragments whose bounds NSTextView honors for caret drawing. Spike scope:

- One `NSTextView` hosting a tiny markdown doc with one table row.
- A hand-written `TableRowFragment` override of `textLineFragments` returning two line fragments side-by-side at different x positions.
- Click left half → caret draws at left fragment's bounds, at natural font height.
- Click right half → caret draws at right fragment's bounds.
- Type a character → inserted at the correct source offset inside the clicked "cell."

**Timebox: 1 day max.** If at end of day the behavior is:
- **Green** (all three checks pass): report findings, proceed to Phase 2.
- **Yellow** (partial — e.g., x is right but height is wrong): report findings, PAUSE and escalate to CD with specific observations. Don't proceed without a plan revision.
- **Red** (line fragment bounds ignored): report findings, PAUSE and escalate. Fallback is NSTextField overlay (spec §3.4), which requires plan rework — CD must ratify before you proceed.

Do NOT commit spike code. Do record findings in a short `spikes/d12_cell_caret/FINDINGS.md` for chronicle purposes.

### Phase 2 — Production implementation

Follow plan Steps 1–10 in order. Key constraints:

1. `TableLayout.cellRanges: [[NSRange]]` — populate in `MarkdownRenderer.visitTable`. Handle GFM `\|` escape, empty cells, optional trailing pipe.
2. `TableRowFragment.textLineFragments` override — per-cell line fragments at natural line height, NOT row height. Padding via `layoutFragmentFrame`, not typographic bounds.
3. **Renderer owns paragraph-style decision** — when a row's layout ID is in `delegate.revealedTables`, the renderer omits `.paragraphStyle` on that row. Strip the Coordinator's `adjustParagraphStyles` helper.
4. `LiveRenderTextView.mouseDown` — single-click → cell caret placement; double-click → whole-table reveal (unless click hits cell content, in which case fall through to macOS default word-select).
5. `Cmd+Shift+E` + `Edit → Edit Table as Source` menu command — always-available path to whole-table source mode. Wire via existing command infrastructure.
6. Cell-boundary keyboard navigation — Tab / Shift+Tab / arrows per spec §3.7.
7. Per-cell selection highlights in `TableRowFragment.draw`.
8. Paste normalization — `\n` → space, pipes → `\|` — only when pasting into a cell range.
9. Undo grouping — verify typing-session coalescing survives renderCurrentText; patch with explicit `beginUndoGrouping`/`endUndoGrouping` if it doesn't.
10. Update D8.1 COMPLETE with a supersession header. Archive D8.1 test plan to `docs/chronicle_by_concept/tables/` (create the directory). Write the D12 test plan at `docs/current_work/testing/d12_per_cell_table_editing_manual_test_plan.md`.

---

## Constraints

- **No `.layoutManager` references.** Engineering-standards §2.2.
- **No storage tricks.** Source is always truth. Cell editing writes to the correct source range; visual cell position is a rendering concern.
- **No modal dialog fallback.** If spike + overlay both fail, STOP and escalate — do not introduce a modal.
- **Double-click inside cell text should still select a word.** Route source-mode trigger to double-click on cell padding / borders, OR rely on menu + keyboard shortcut as the primary trigger. Either way, don't break the macOS word-select convention.
- **D8 read-only grid rendering, D9 scroll-to-line, D10 line numbers, D11 CLI view-state, delimiter reveal all keep working.** Regression = blocker.
- **Dogfood before declaring done.** Open `docs/roadmap_ref.md`, click into the Status cell of D5, type, verify caret position + size + typing behavior. Then open `docs/competitive-analysis.md` (multiple tables), exercise cross-table navigation.

---

## Success Criteria

- [ ] Spike reported Green, OR CD ratified an alternative path after Yellow/Red.
- [ ] Single-click in any grid cell places caret at the click position *inside the cell* at natural font line height. Grid stays rendered.
- [ ] Typing in a cell inserts characters into the cell's source content; grid re-renders cleanly; caret stays visually in the cell.
- [ ] Tab / Shift+Tab cycles through cells. Arrow keys cross cell boundaries correctly.
- [ ] Double-click in cell padding (or menu / keyboard shortcut) drops to whole-table source mode. Caret in source mode is correctly positioned and at natural line height — the D8.1 caret bug is fixed.
- [ ] Drag-select across cells renders per-cell highlights.
- [ ] Cmd+Z undoes a cell-edit session as one operation.
- [ ] `grep -r '\.layoutManager' Sources/` clean.
- [ ] D8, D9, D10, D11 still work.
- [ ] Manual test plan at `docs/current_work/testing/d12_per_cell_table_editing_manual_test_plan.md` covers all spec §4 criteria.

---

## On Completion

1. Create `docs/current_work/stepwise_results/d12_per_cell_table_editing_COMPLETE.md`:
   - What shipped (cell-level editing primary + double-click source secondary).
   - Files modified / created.
   - Findings (expect: line-fragment gotchas, keyboard-nav edge cases, selection-rendering subtleties).
   - Deviations from spec + plan.
   - Spike results summary.
2. Update `docs/roadmap_ref.md`:
   - D12 row → ✅ Complete.
   - D8.1 row → **Superseded by D12 (YYYY-MM-DD)**.
   - New change-log entry.
3. Update `docs/current_work/stepwise_results/d08_1_table_reveal_COMPLETE.md` with a header note pointing to D12.
4. Archive `docs/current_work/testing/d08_1_manual_test_plan.md` → `docs/chronicle_by_concept/tables/d08_1_manual_test_plan.md`.
5. Update Harmoniq project #53 task #1386: set current_status to `completed`, description-append a pointer to the D12 deliverable in-repo.
6. Commit + push.
