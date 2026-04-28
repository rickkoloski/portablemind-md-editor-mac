# 05 — Tables (current implementation)

## Overview

Two deliverables that replaced six earlier ones (see `04_tables_tk2_retired` for the museum exhibit). D16 spiked TextKit 1's native `NSTextTable` / `NSTextTableBlock` against the four canonical scenarios that broke under TextKit 2; D17 ported the editor's text view from the TK2 custom-fragment table system to TK1, deleting ~3,200 lines of custom-layout machinery.

This is the **current implementation** of markdown table editing. Per-cell editing, click-into-wrapped-cells, scroll-jump-on-typing — all native TK1 behavior, no custom layout code. The decision was: stop trying to make TK2 do something it isn't designed to do. TextEdit (Apple's own reference markdown / RTF editor) falls back to TK1 NSTextTable for tables for the same reason.

## Deliverables

| File prefix | Deliverable | What it produced |
|---|---|---|
| `d16_textkit1_tables_spike` | Bounded TK1 spike at `spikes/d16_textkit1_tables/` | All four canonical scenarios GREEN: click-into-wrapped-cell, multi-row table layout, source round-trip, scroll-on-edit. Recommendation: migrate. |
| `d17_textkit1_migration` | Production migration: TK2 fragments → TK1 NSTextTable | Retired D8 (table render), D8.1 (reveal), D12 (per-cell), D13 (overlay + modal), and the D15.1 scroll-suppression workarounds — ~3,200 lines deleted. |

## Common Tasks

- **"How does the editor render a markdown table today?"** → `specs/d17_textkit1_migration_spec.md` § "Implementation". `Sources/Editor/Renderer/Tables/` builds `NSTextTable` / `NSTextTableBlock` from parsed GFM tables; the rest of the rendering chain (`NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView`) is stock TextKit 1.
- **"How does cell-level editing work?"** → Stock TK1 behavior. Click into a cell, the caret lands; edit; navigate between cells with arrow keys / Tab. There is no custom cell-edit overlay (D13's overlay was retired by D17).
- **"What happened to the modal cell popout?"** → Dropped per D17 spec § 5. TK1's in-place editing makes it unnecessary. The modal popout idea is parked as a future home for inline-content / rich-content editing if we ever need it (notes preserved in D13's spec for reference, in `04_tables_tk2_retired`).
- **"What changed in `LiveRenderTextView` between TK2 and TK1?"** → D17 COMPLETE captures the diff. Most of the cell-routing complexity (`CellSelectionDataSource`, `cellRanges`, `cellLocalCaretIndex`, `mouseDown`/`keyDown` cell-aware hooks) is gone — TK1 handles it natively.

## Key Decisions Recorded

| Date | Decision | Where |
|---|---|---|
| 2026-04-26 | **D16 spike GREEN across the four canonical scenarios** (wrapped-cell click, multi-row, round-trip, scroll). Migrate. | D16 COMPLETE |
| 2026-04-26 | **D17 retires D8/D8.1/D12/D13/D15.1** wholesale. Modal popout dropped per spec § 5. | D17 COMPLETE |
| 2026-04-26 | **`LiveRenderTextView` uses `layoutManager` (`NSLayoutManager`)**, not `textLayoutManager`. The TK2 path is a runtime trip-wire (asserts `textLayoutManager == nil`). | `docs/engineering-standards_ref.md` §3 (D17, 2026-04-26 onwards) |

## Dependencies

- **Predecessor:** `04_tables_tk2_retired` — the deliverables this concept replaced. Read that concept's `_index.md` to understand *why* TK1 was chosen, but do not consult it for current behavior.
- **Predecessors that survived the migration:** `01_foundation` (project + TK2 *for non-tables*), `02_authoring_basics` (mutation primitives), `03_workspace` (sidebar + tabs).
- **Successor:** `06_persistence_and_connectors` (D14 save, D18 PM tree, D19 PM save-back) — D14's atomic-write semantics work for any markdown content, including tables rendered via TK1.
