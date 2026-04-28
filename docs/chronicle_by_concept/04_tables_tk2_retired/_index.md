# 04 — Tables (TK2, Retired)

> ## ⚠️ HISTORICAL ONLY — Retired 2026-04-26 by D17
>
> **None of the code, fragment math, or design decisions in this concept are live in the editor today.** TextKit 2's lazy-layout-with-custom-fragment-heights model could not be tamed for in-place markdown table editing. Six deliverables (D8, D8.1, D12, D13, D15, D15.1) tried; D17 deleted ~3,200 lines of custom-layout machinery in favor of native TextKit 1 (`NSTextTable` / `NSTextTableBlock`) — see `05_tables` for the current implementation.
>
> **What this concept is good for:** the *why-we-chose-TK1* narrative. Read this if you (or another agent) start arguing that "we should just fix the TK2 fragment system" — the artifacts here are the documented record that we tried that for six deliverables and it didn't converge.
>
> **What this concept is NOT good for:** building current behavior, debugging the live editor, or designing new table features. For all of those, go to `05_tables`.

---

## Overview

This concept covers the TextKit 2 era of markdown table support, from the first fragment-grid render through three rounds of cell-editing UX (in-place, overlay, modal popout) and two diagnosis passes on the recurring scroll-jump bug. The thread starts with D8 (table rendering, 2026-04-23) and ends with D15.1's decision to abandon TK2 for tables (2026-04-26).

The architectural friction was specific to **tables**: the rest of the editor's markdown rendering (headings, bold, code blocks, etc.) sat on TK2 just fine. Tables broke because TK2's lazy-layout-with-custom-fragment-heights doesn't honor multi-cell row geometry, doesn't expose visual-line bounds inside wrapped cells, and re-fragments aggressively on storage edits.

## Deliverables

| File prefix | Deliverable | What it tried | Why it didn't survive |
|---|---|---|---|
| `d08_table_rendering` | TK2 GFM tables via `NSTextLayoutFragment` custom grid | Render pipe-tables as a visual grid with per-cell layout via custom fragments | Foundation for everything below; superseded wholesale by D17 |
| `d08_1_table_reveal` | Caret-on-table reveals to pipe-source mode | Click into a table → temporarily reveal source for editing → leave → grid returns | Whole-table source reveal was jarring; D12 attempted to replace it with per-cell editing |
| `d12_per_cell_table_editing` | Single-click places caret inside a cell at natural height | Cell-level interaction without dropping out of grid mode | Worked for single-line cells; failed for wrapped cells (visual line 2 unreachable) |
| `d13_cell_edit_overlay` | Numbers/Excel-style inline overlay text view per active cell | Sidestep TK2's source-fragment-contiguity constraint with a separate NSTextView | Spike GREEN, production shipped, dogfood still surfaced wrap + scroll bugs |
| `d15_scroll_jump_fix` | Symptom-patch: save+restore scrollY around `renderCurrentText` | Stop the editor from scrolling on every keystroke | Treated the symptom; D15.1 went after the cause |
| `d15_1_scroll_jump_root_cause` | Root-cause investigation across keyDown / mouseDown / re-fragmentation | Multiple targeted TK2 fixes (scroll guards, full-doc `ensureLayout`, post-scroll fragment re-resolution) | Each fix worked in isolation; combined dogfood still leaked visual bugs. **Decision recorded: stop fighting TK2 for tables; spike TK1.** |

## Common Tasks (for the museum visitor)

- **"Why didn't we fix the TK2 fragment system?"** → Read `results/d15_1_scroll_jump_root_cause_COMPLETE.md`. The document captures the architectural diagnosis.
- **"What did per-cell editing look like before TK1?"** → `specs/d12_per_cell_table_editing_spec.md`, `specs/d13_cell_edit_overlay_spec.md`. Note the multi-tier spike + production split — the Numbers/Excel overlay pattern was a real attempt, not abandoned lightly.
- **"What artifacts survived from this era?"** → The debug HUD, harness regression scaffolding, and inspect tooling (introduced during D15.1) carried forward into D16/D17 and beyond. Listed in the D15.1 COMPLETE.

## Key Decisions Recorded

| Date | Decision | Where |
|---|---|---|
| 2026-04-26 | **Stop fighting TK2 for tables.** Spike TK1. | D15.1 COMPLETE |
| 2026-04-26 | TK1 spike GREEN across the four canonical scenarios → migrate. | D16 COMPLETE (in `05_tables`) |

## Dependencies

- **Predecessor concepts:** `01_foundation` (TK2 spike + project), `02_authoring_basics` (mutation primitives), `03_workspace` (sidebar + tabs).
- **Superseded by:** `05_tables` (D16 spike + D17 migration). The migration retired everything in this folder; pre-D17 commits remain on `main`'s history but no live code references this work.
- **Cross-cutting reuse:** harness command-poller pattern + accessibility-identifier discipline, both of which originated here, are still in use everywhere.
