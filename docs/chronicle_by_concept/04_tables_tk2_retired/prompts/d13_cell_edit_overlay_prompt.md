## D13: Cell-Edit Overlay — CC Prompt

**Spec:** `docs/current_work/specs/d13_cell_edit_overlay_spec.md`
**Plan:** `docs/current_work/planning/d13_cell_edit_overlay_plan.md`
**Spike (validated):** `spikes/d13_overlay/` + `spikes/d13_overlay/FINDINGS.md`

---

## Context

D12 shipped per-cell editing for single-line table cells; wrapped cells revealed the architectural limit that motivates D13 — `NSTextLineFragment` requires contiguous source ranges, so the caret cannot natively traverse visual lines of a wrapped cell when the row contains multiple cells.

D13 introduces a **cell-edit overlay** (Numbers/Excel pattern): on single-click, an in-place reusable NSTextView mounts over the cell, displays the cell's source content, and accepts edits. Click-to-caret math (validated in spike Tier 2) places the caret on the correct visual line. On commit (Enter/Tab/click-out/scroll/focus-loss), the overlay's text splices back into the cell's source range with pipe-escape + newline normalization.

D13 also introduces a **modal popout** (spec §3.12) — a centered window with a plain text editor for the cell's source, opened via right-click → "Edit Cell in Popout…". This is the always-available power option AND the future home for content the overlay's math can't handle (inline images, complex inline markdown). V1 = explicit user choice only; auto-fallback on detected unhandled content is V1.x.

**Pre-users principle.** No shortcuts. Match Numbers/Excel feel. CD direction (2026-04-25): "If this can't be fixed, I'm not sure I won't abandon the project." Spike answered GREEN; production is the merge.

**Spike findings carry forward as design references.** Spike code itself is throwaway; the math algorithm, anchor pattern for Tab nav, and visual continuity rules are inputs to this implementation. See `spikes/d13_overlay/FINDINGS.md` § "Production-merge constraints" for the 12 decisions that the spike validated and that production must preserve.

**Read before starting:**

- `docs/current_work/specs/d13_cell_edit_overlay_spec.md` (full behavior contract — note §3.7 active-cell border, §3.10 D12 retention, §3.12 modal popout, §3.13 handoff rules, §6 resolved open questions)
- `docs/current_work/planning/d13_cell_edit_overlay_plan.md` (per-phase plan with automated test gates)
- `spikes/d13_overlay/FINDINGS.md` (math algorithm, production-merge constraints, GREEN go/no-go)
- `Sources/Editor/Renderer/Tables/TableLayout.swift` (where cellLocalCaretIndex lands)
- `Sources/Editor/Renderer/Tables/TableRowFragment.swift` (cell drawing reference)
- `Sources/Editor/Renderer/Tables/CellSelectionDataSource.swift` (D12 — STAYS for non-overlay routing)
- `Sources/Editor/EditorContainer.swift` (Coordinator — wires the controller)
- `Sources/Editor/LiveRenderTextView.swift` (mouseDown integration; remove `snapCaretToCellContent`)
- `Sources/Debug/HarnessCommandPoller.swift` (D12 harness — extends with D13 actions)
- `docs/current_work/stepwise_results/d12_per_cell_table_editing_COMPLETE.md` (header note: D12 in-cell caret superseded by D13)

---

## Task

Implement D13 per the spec + plan. Six phases with **automated test gates** between each. Per CD direction (2026-04-26): "automated testing at each phase would be a solid step to enforce."

**Operating model: autonomous through the phases.** CD is in/out on Sundays; surface decisions only when blocked. Otherwise:
- Read spec/plan/spike findings.
- Implement Phase N.
- Run Phase N's automated test gate. Fix any failures before commit.
- Commit Phase N with a descriptive message; reference test results.
- Proceed to Phase N+1.

**When to surface to CD:**
- A test gate fails in a way that suggests a spec change (not just a bug fix).
- A spec ambiguity blocks progress.
- An unexpected regression in D8/D9/D10/D11/D8.1/D12.
- A scope question about V1 vs V1.x (e.g., the modal's auto-fallback on unhandled content — defer per spec).

### Phase order + key constraints

1. **`TableLayout.cellLocalCaretIndex`** — port spike algorithm verbatim. Unit + harness tests.
2. **`CellEditOverlay` + `CellEditController`** — show/hide/commit/cancel. Active-cell border per §3.7.
3. **`LiveRenderTextView.mouseDown`** — single-click → overlay. Remove `snapCaretToCellContent`. Preserve double-click reveal.
4. **Tab nav + scroll observer.** Header excluded from cycle. Anchor-based table re-find post-commit.
5. **Modal popout** — right-click menu + window + handoff rules (§3.13).
6. **Manual test plan + COMPLETE doc + roadmap update + tag `v0.2`.**

### Phase commit pattern

```
D13 Phase N — <one-line summary>

<2-4 line description: what changed, what's verified>

<test results summary: which automated tests passed, manual sanity checks>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Constraints

- **No `.layoutManager` references.** Engineering-standards §2.2.
- **Source is truth.** Cell content lives in the markdown buffer; overlay/modal hold derived state until commit.
- **No modal-only fallback.** Both overlay AND modal must work; right-click menu must include "Edit Cell in Popout…" for the explicit-user-choice path.
- **Header cells excluded from Tab cycle** (Numbers/Excel convention). Direct-click on a header still mounts the overlay.
- **Spike code at `spikes/d13_overlay/` is reference, not migration target.** Don't copy files; reimplement against production conventions.
- **Pre-users principle.** No "good enough" shortcuts. Math + UX must match Numbers/Excel for plain-text cells.
- **D8.1 reveal mechanism stays** — double-click drops to whole-row source mode (D12 retained); single-click in revealed row goes through default NSTextView path (NOT overlay).
- **`renderCurrentText` is the production re-render entry point** — call after every commit; don't reimplement table rendering inside the controller.
- **Harness extensions go in `Sources/Debug/HarnessCommandPoller.swift`** with `// TEST-HARNESS:` markers per project convention.

---

## Per-phase test gate enforcement

**Each phase's commit must pass its automated test gate before moving to the next.** Test gates are in `docs/current_work/planning/d13_cell_edit_overlay_plan.md` under each phase. Quick reference:

| Phase | Gate |
|---|---|
| 1 | Unit tests + harness `query_caret_for_click` for all 7 spec §3.5 cases |
| 2 | Lifecycle round-trip (show / type / commit / cancel / re-show) + visual baseline |
| 3 | Synthetic-click → overlay → caret-position chain (the PRIMARY case) |
| 4 | Tab cycle incl. cross-row + boundary dismiss + header exclusion + scroll-commit |
| 5 | Modal lifecycle + handoff (overlay→modal, same-cell omit) |
| 6 | Full regression suite green; manual test plan; COMPLETE doc; roadmap; tag |

If a gate fails:
1. Surface the failure inline in the session.
2. Diagnose root cause; fix or escalate.
3. Re-run gate. Don't commit until green.

---

## Success criteria

Mirror spec §4 (overlay path + modal path + regression). Briefly:

- Single-click in any cell → overlay at click position with caret on right visual line (incl. wrapped cell visual line 2+).
- Type / Enter (commit) / Tab (advance) / Escape (cancel) / click-out (commit) / scroll (commit) all work.
- Active-cell border visible (2.0pt accent); text position invariant.
- Right-click → menu has "Edit Cell in Popout…"; modal opens centered, edits, saves with pipe-escape, cancels cleanly.
- Handoff: right-click on cell B while overlay on A → A commits, modal on B.
- Header cells: direct-click works, Tab cycle skips them.
- D8/D9/D10/D11/D8.1/D12 regressions: none.
- `grep -r '\.layoutManager' Sources/` clean.

---

## On Completion (Phase 6)

1. Write `docs/current_work/stepwise_results/d13_cell_edit_overlay_COMPLETE.md`:
   - What shipped (overlay + modal popout).
   - Files modified / created.
   - Automated test summary (per phase).
   - Findings vs spec (deviations, additions).
   - Spike → production translation notes.
2. Update `docs/roadmap_ref.md`:
   - D13 row → ✅ Complete — 2026-04-XX.
   - D13.1 row added if appropriate (e.g., "Inline-markdown rendering inside cells / modal" deferred).
   - Change-log entry summarizing.
3. Update `docs/current_work/stepwise_results/d12_per_cell_table_editing_COMPLETE.md`:
   - Header note: "D12's wrapped-cell limitation resolved by D13 cell-edit overlay (2026-04-XX). D12 mechanisms (cellRanges, CellSelectionDataSource, double-click reveal, cell-boundary nav) all retained."
4. Update HYDRATION.md if it exists with D13 status.
5. `git tag v0.2 -a -m "D13 cell-edit overlay shipped"` and push.
6. Confirm with CD before tagging if any phase was YELLOW (escalated decisions accepted).

---

## Spike code retention

Spike at `spikes/d13_overlay/` stays committed. After D13 production ships, the spike is frozen for reference (per `spikes/d01_textkit2/` precedent). Don't delete; don't modify.

The spike's harness pattern, `cellLocalCaretIndex` algorithm, anchor-based Tab navigation, and active-cell border integration are the canonical references for any future maintainer asking "why was this designed this way?"
