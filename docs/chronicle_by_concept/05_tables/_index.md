# 05 — Tables (current implementation)

## Overview

Four deliverables that replaced six earlier ones (see `04_tables_tk2_retired` for the museum exhibit) and then evolved the column-layout algorithm twice. D16 spiked TextKit 1's native `NSTextTable` / `NSTextTableBlock` against the four canonical scenarios that broke under TextKit 2; D17 ported the editor's text view from the TK2 custom-fragment table system to TK1, deleting ~3,200 lines of custom-layout machinery. D24 made column widths responsive to viewport — short-token columns hug their content, long-text columns share remaining space proportionally, resize reflows via 100ms-debounced re-render. D24.2 replaced D24's "lock-in by equal-share + flex-by-natural" body with the canonical CSS Tables §3.9 slack-proportional algorithm plus a deliberate divergence (Q8 narrow-column threshold lock-in) so dates / IDs / statuses stay at content width even at narrow viewports.

This is the **current implementation** of markdown table editing + layout. Per-cell editing, click-into-wrapped-cells, scroll-jump-on-typing — all native TK1 behavior, no custom layout code. Column widths flex responsively via `TableColumnDistribution.distribute` (a pure function with 23 XCTest fixtures). The decision was: stop trying to make TK2 do something it isn't designed to do. TextEdit (Apple's own reference markdown / RTF editor) falls back to TK1 NSTextTable for tables for the same reason.

## Deliverables

| File prefix | Deliverable | What it produced |
|---|---|---|
| `d16_textkit1_tables_spike` | Bounded TK1 spike at `spikes/d16_textkit1_tables/` | All four canonical scenarios GREEN: click-into-wrapped-cell, multi-row table layout, source round-trip, scroll-on-edit. Recommendation: migrate. |
| `d17_textkit1_migration` | Production migration: TK2 fragments → TK1 NSTextTable | Retired D8 (table render), D8.1 (reveal), D12 (per-cell), D13 (overlay + modal), and the D15.1 scroll-suppression workarounds — ~3,200 lines deleted. |
| `d24_responsive_table_columns` | Responsive table column layout (resolves backlog **i02**) | Removed the 320pt cap; 3-pass build (measure → distribute → apply) with content-hash-keyed natural-width cache; pure-function `TableColumnDistribution.distribute` with 15 XCTest fixtures; `byWordWrapping` cell line-break mode (Q9 — phase 1 spike falsified `byTruncatingTail`); 100ms-debounced reflow on `NSWindow.didResizeNotification`. New `MdEditorUnitTests` target at `UnitTests/`. Three new harness actions: `dump_table_natural_widths`, `dump_table_layout`, `set_window_width`. |
| `d24.2_slack_proportional_columns` | Slack-proportional column distribution (resolves backlog **i05** + **i06**) | Distribution rewrite from "lock-in by equal-share + flex-by-natural" to CSS Tables §3.9 `min-content + max-content + slack-proportional` plus Q8 narrow-column threshold lock-in (`max ≤ 120pt` → pre-locked at max regardless of slack). `(min, max)` per-column measurement; three-regime distribute (`fits` / `slack` / `overflow`); Q1 token-split heuristic for min-content. Latent `NSTextContainer.lineFragmentPadding` compensation added in-deliverable (cell `contentWidth += 2 × 5pt`; `cellFramingOverhead` 14 → 24). 23 XCTest fixtures. Harness emits `regime` + `narrowThreshold` for transparency. |

## Common Tasks

- **"How does the editor render a markdown table today?"** → `specs/d17_textkit1_migration_spec.md` § "Implementation". `Sources/Editor/Renderer/Tables/` builds `NSTextTable` / `NSTextTableBlock` from parsed GFM tables; the rest of the rendering chain (`NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView`) is stock TextKit 1.
- **"How does cell-level editing work?"** → Stock TK1 behavior. Click into a cell, the caret lands; edit; navigate between cells with arrow keys / Tab. There is no custom cell-edit overlay (D13's overlay was retired by D17).
- **"What happened to the modal cell popout?"** → Dropped per D17 spec § 5. TK1's in-place editing makes it unnecessary. The modal popout idea is parked as a future home for inline-content / rich-content editing if we ever need it (notes preserved in D13's spec for reference, in `04_tables_tk2_retired`).
- **"What changed in `LiveRenderTextView` between TK2 and TK1?"** → D17 COMPLETE captures the diff. Most of the cell-routing complexity (`CellSelectionDataSource`, `cellRanges`, `cellLocalCaretIndex`, `mouseDown`/`keyDown` cell-aware hooks) is gone — TK1 handles it natively.
- **"How are column widths chosen today?"** → Three passes in `TK1TableBuilder.build(...)`: Pass 1 measures `(min, max)` per column via `cellMinContentWidth` (Q1 token-split) and `cellNaturalText`, populates `TableNaturalWidthCache` keyed by content hash. Pass 2 calls `TableColumnDistribution.distribute(measurements:viewportWidth:minWidthFloor:narrowThreshold:)` — pure function, applies Q8 lock-in (`max ≤ 120pt` columns pre-locked at max with "leaves room for remaining mins" constraint), then slack-proportional flex over remaining pool, then post-pass floor clamp. Pass 3 wires applied widths into `NSTextTableBlock.setContentWidth`. Resize-only reflows hit the cache and skip Pass 1.
- **"What's the algorithm regime if a table looks wrong?"** → `dump_table_layout` harness action emits `regime: "fits" | "slack" | "overflow"`. `fits` = Σmax ≤ viewport (columns at max). `slack` = between (Q8 lock + slack-proportional). `overflow` = Σmin ≥ viewport (columns at min; table extends past editor right edge). Floor clamp can pull values up post-pass; sum may exceed viewport per Q3.
- **"Why is `cellFramingOverhead` 24pt and not 14pt?"** → 14pt is border + padding (D24 baseline); D24.2 added 10pt for `2 × NSTextContainer.lineFragmentPadding` (default 5pt each side). Without this, applied column width didn't equal actual usable text area — columns near the wrap threshold would flicker during drag-resize. `makeCell` also pads `contentWidth` by `2 × cellLineFragmentPadding` so usable text area equals algorithm-applied width.
- **"How do I drive table-layout from the harness?"** → Three actions: `dump_table_natural_widths` (cache state + `(min, max)` per column), `dump_table_layout` (applied widths + regime + narrowThreshold + per-cell `contentWidth`), `set_window_width` (drives window resize → debounced reflow). Recipes in `testing/d24_responsive_table_columns_manual_test_plan.md`.

## Key Decisions Recorded

| Date | Decision | Where |
|---|---|---|
| 2026-04-26 | **D16 spike GREEN across the four canonical scenarios** (wrapped-cell click, multi-row, round-trip, scroll). Migrate. | D16 COMPLETE |
| 2026-04-26 | **D17 retires D8/D8.1/D12/D13/D15.1** wholesale. Modal popout dropped per spec § 5. | D17 COMPLETE |
| 2026-04-26 | **`LiveRenderTextView` uses `layoutManager` (`NSLayoutManager`)**, not `textLayoutManager`. The TK2 path is a runtime trip-wire (asserts `textLayoutManager == nil`). | `docs/engineering-standards_ref.md` §3 (D17, 2026-04-26 onwards) |
| 2026-05-04 | **Cell line-break mode is `byWordWrapping`, not `byTruncatingTail`** (Q9). D24 phase 1 spike empirically falsified the spec's original `byTruncatingTail` plan — it's a single-line truncation mode under TK1 NSLayoutManager, never multi-line wrap. The `+1 phase` RED fallback (custom `NSLayoutManager` hook) was avoided. | D24 spec Q9 (added 2026-05-04) |
| 2026-05-05 | **Distribution is a pure function** (`TableColumnDistribution.distribute`) with unit-test fixtures, decoupled from `NSTextTable` builder so the algorithm can be exercised without an NSWindow. | D24 plan §Phase 3 |
| 2026-05-05 | **Natural-width cache is content-hash-keyed**, so resize hits the cache and skips Pass 1. Same column content across multiple tables in the same doc shares an entry. | D24 phase 2 |
| 2026-05-05 | **Window-resize debounce 100ms** (`NSWindow.didResizeNotification` → `Task.sleep(100ms)` tail → `renderCurrentText`). Tracks live viewport without dragging chrome jank. | D24 phase 5 |
| 2026-05-06 | **Q8 narrow-column threshold lock-in** — columns with `max ≤ 120pt` pre-lock at max regardless of slack. Deliberate divergence from CSS Tables §3.9 for the data-editor case (dates / IDs / statuses stay single-line at narrow viewports). Threshold tunable per-call. | D24.2 spec Q8 |
| 2026-05-06 | **`NSTextContainer.lineFragmentPadding` compensation** — cell `contentWidth = appliedWidth + 2 × lineFragmentPadding` (10pt). D24 had ≥3pt headroom that masked it; D24.2's Q8 locks AT max so the gap bit. Surfaced live in phase 3 smoke (i06). | D24.2 deviation §1 |
| 2026-05-06 | **Q1 token-split heuristic** — atomize cell content on whitespace + ASCII soft-break punctuation (`-`, `/`, `.`). 0.0% delta from hand-derived expected atom widths across 8 fixtures. CJK / RTL / emoji deferred. | D24.2 spec Q1 + spike |

## Dependencies

- **Predecessor:** `04_tables_tk2_retired` — the deliverables this concept replaced. Read that concept's `_index.md` to understand *why* TK1 was chosen, but do not consult it for current behavior.
- **Predecessors that survived the migration:** `01_foundation` (project + TK2 *for non-tables*), `02_authoring_basics` (mutation primitives), `03_workspace` (sidebar + tabs).
- **Successor:** `06_persistence_and_connectors` (D14 save, D18 PM tree, D19 PM save-back, D23 + D23.1 PM file management) — D14's atomic-write semantics work for any markdown content, including tables rendered via TK1.
- **Open follow-ups:** D17 full manual interactive walk (Tab navigation); `signpost`-instrumented resize performance profile; user-resizable columns; persistent per-doc column-width preference; CJK / RTL / emoji break-opportunity rules; horizontal scroll for `overflow` regime.
