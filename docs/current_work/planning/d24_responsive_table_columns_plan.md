# D24 Plan — Responsive table column layout

**Spec:** `docs/current_work/specs/d24_responsive_table_columns_spec.md`
**Created:** 2026-04-28
**Branch:** `feature/d24-responsive-table-columns`

---

## 0. Approach

Six phases. Phase 1 is a spike (gates the algorithm on TextKit behavior we claim but haven't verified). Phases 2-5 implement the algorithm bottom-up: measure → distribute → apply → reflow. Phase 6 closes the deliverable with manual test plan + COMPLETE + roadmap.

1. **Spike: validate `byTruncatingTail` multi-line behavior.** Bounded; gates Q8.
2. **`natural_width` measurement + cache.** Pass 1 implementation + cache invalidation infrastructure.
3. **Distribution algorithm.** Pass 2 — lock-in + proportional. Pure function; unit-testable.
4. **Apply to `NSTextTable` + paragraph styles.** Pass 3 — wire computed widths into the existing TK1 table builder; set cell line-break mode.
5. **Resize debounce + reflow triggers.** Window-resize handling (Q3 decision).
6. **Manual test plan + COMPLETE + roadmap.**

Each phase ends in a commit. Stop and surface a `**Question:**` if a phase reveals scope drift (e.g., the spike contradicts Q8).

---

## 0.1. Verification approach (harness-first)

D24 continues the harness-first verification approach established in D18 plan §0.1 and exercised in D19. New harness affordances per phase:

- **Phase 1 (spike):** ad-hoc; spike harness lives in `spikes/d24_table_columns/` and is discarded after.
- **Phase 2:** new `dump_table_natural_widths {tableIndex, resultPath}` action — emits per-column natural widths for the Nth table in the focused doc. Lets test drivers assert measurement correctness.
- **Phase 3:** distribution is a pure function over `(naturalWidths: [CGFloat], viewportWidth: CGFloat) -> [CGFloat]`. Unit tests in a new `Tests/TableLayout/` directory; no harness action needed for the math itself.
- **Phase 4:** new `dump_table_layout {tableIndex, resultPath}` action — emits the per-column **applied** widths (post-distribution, post-NSTextTableBlock) so test drivers can verify what the user actually sees. Plus extends `dump_save_state`'s pattern to expose the cached natural-widths so test drivers can assert cache hit/miss.
- **Phase 5:** new `set_window_width {pt}` action — programmatic window-width resize so the test driver can drive the responsive behavior without dragging the window. Existing `dump_table_layout` confirms the post-resize result.
- **Phase 6:** harness-driven assertion of all spec acceptance criteria via the actions above; manual test plan covers the same scenarios for someone without the driver.

---

## Phase 1 — Spike: validate `byTruncatingTail` multi-line behavior

**Goal:** Validate Q8's claim that `NSParagraphStyle.lineBreakMode = .byTruncatingTail` on a TK1 NSTextTable cell with no `numberOfLines` cap produces:
- Word-wrap at boundaries normally for ordinary text
- Over-long unbreakable tokens pushed to their own line
- Ellipsis on the over-long-token line if it still doesn't fit
- Subsequent paragraph content below continues to wrap normally

If the behavior matches: proceed to phase 2 with confidence. If it differs: fall back to the documented plan B (custom layout-manager hook).

**Approach (decided 2026-04-28):** **offscreen / programmatic** spike. No NSWindow, no NSTextView host. Build NSTextStorage + NSLayoutManager + NSTextContainer directly, force layout at three widths (wide / medium / narrow), render to PNG via `NSImage` lockFocus, dump per-line fragment info to stdout. Zero focus impact — important because the spike will land alongside an upcoming demo where `feedback_focus_stealing.md` matters more than usual. The small risk: TK1 NSTextTable cell layout might differ subtly between "raw NSLayoutManager" and "embedded in a real NSTextView". If the offscreen results don't match the visual reality (cross-checked once against the production editor on a hand-rolled fixture doc), fall back to a visual spike with `NSApp.setActivationPolicy(.accessory)` so it doesn't grab focus.

**Files created:**

- `spikes/d24_table_columns/run_spike.swift` — single self-contained Swift script. Run via `swift run_spike.swift`. Builds the table layout for three test cells (normal multi-paragraph text, over-long URL only, mixed text + over-long URL); lays out at 600pt / 400pt / 280pt container widths; emits per-line fragment info to stdout AND renders PNG snapshots to `spikes/d24_table_columns/results/`.
- `spikes/d24_table_columns/README.md` — spike scope, what to look for, GREEN/YELLOW/RED criteria + observed behavior + recommendation.

**DOD:**

- Spike script builds and runs.
- All four expected behaviors observed in either the per-line fragment info or the PNG snapshots (or both), pasted into the spike README.
- Recommendation in spike README: **GREEN** (proceed with byTruncatingTail), **YELLOW** (proceed but with a documented gotcha), or **RED** (fall back to custom NSLayoutManager hook).

**Commit:** `D24 phase 1 — spike: validate byTruncatingTail multi-line behavior on TK1 cells`

---

## Phase 2 — `natural_width` measurement + cache

**Goal:** Compute and cache the `natural_width` for every column in every rendered table. Pure measurement — no widths applied yet. The existing TK1 table builder still uses its 320pt-cap heuristic; phase 4 swaps it.

**Files updated:**

- `Sources/Editor/Renderer/Tables/TK1TableBuilder.swift` (or successor — locate via `grep -rn 'columnCap'`):
  - Add `private func measureNaturalWidth(cells: [NSAttributedString]) -> CGFloat` — CoreText shaping pass per cell, returns longest single-line width.
  - Wire to a new module-internal `TableNaturalWidthCache` keyed on `(table_anchor, content_hash_of_cells)` per column.
  - Call sites: every place the builder runs through cells for a table, populate / read from the cache.

**Files created:**

- `Sources/Editor/Renderer/Tables/TableNaturalWidthCache.swift` — actor-isolated dict keyed on `(NSAttributedString stable id, contentHash)`. Hit/miss instrumentation for harness reads.

**Harness actions added:**

- `dump_table_natural_widths {tableIndex, resultPath}` — emits `[col_index, natural_width_pt, cache_hit]` for the `tableIndex`-th table in the focused doc.

**DOD:**

- Build clean.
- For a doc with three tables of varying complexity, `dump_table_natural_widths` emits sensible per-column widths (sanity check: Decision-log "Date" column < 100pt, "Decision" column = many hundreds pt).
- Cache: identical content → cache hit on second read. Edit a cell → cache miss → re-measure.
- D17 manual test plan rerun GREEN — no behavior change yet (cap still in place).

**Commit:** `D24 phase 2 — natural_width measurement + per-table cache`

---

## Phase 3 — Distribution algorithm (pure function)

**Goal:** Implement Pass 2 from the spec as a pure function. Unit-tested via XCTest (no harness needed; the function takes/returns plain values).

**Files created:**

- `Sources/Editor/Renderer/Tables/TableColumnDistribution.swift` — single public function:
  ```swift
  enum TableColumnDistribution {
      /// - Parameter naturalWidths: per-column natural width (capped at viewportWidth per Q8).
      /// - Parameter viewportWidth: container width inside the editor's text container.
      /// - Returns: per-column applied widths summing to ≤ viewportWidth (or > viewportWidth only when min_width × n > viewportWidth, per Pass 2 floor-wins branch).
      static func distribute(
          naturalWidths: [CGFloat],
          viewportWidth: CGFloat,
          minWidthFloor: CGFloat = 60.0
      ) -> [CGFloat]
  }
  ```
- `UITests/TableColumnDistributionTests.swift` (XCTest) — fixtures matching the spec's edge cases:
  - All fits naturally (sum ≤ viewport)
  - Some lock, others flex
  - All flex (no narrow columns)
  - One super-long, rest narrow
  - All narrow (every column locks)
  - Many narrow + one wide (the Decision-log shape)
  - Single column
  - Empty table (degenerate; assert preserved behavior)
  - Floor wins (viewport < 60 × n)

**DOD:**

- All XCTest cases pass.
- Distribution is deterministic — same inputs → same outputs.
- Sum-of-widths invariant: `Σ widths ≤ viewport` unless floor-wins branch fired (in which case `Σ widths == minWidthFloor × n`).
- No mutable state; the function is `static` and side-effect-free.

**Commit:** `D24 phase 3 — distribution algorithm (pure function + unit tests)`

---

## Phase 4 — Apply to NSTextTable + cell line-break mode

**Goal:** Replace the existing 320pt-cap heuristic with the new distribution. Set per-cell `byTruncatingTail` line-break mode (Q8). Visible milestone: the responsive layout reaches the user.

**Files updated:**

- `Sources/Editor/Renderer/Tables/TK1TableBuilder.swift`:
  - Remove the `columnCap: CGFloat = 320` constant.
  - At table-build time: read `viewportWidth` from `NSTextContainer.containerSize.width`, read cached natural widths, call `TableColumnDistribution.distribute(...)`, apply per-column widths via `NSTextTableBlock.setValue(_:type:.absoluteValueType, for:.width)`.
  - Set every cell's paragraph style `lineBreakMode = .byTruncatingTail`.
- `Sources/Editor/EditorContainer.swift` (or wherever the text container's size is owned):
  - Expose a way to read the current container width to the table builder.

**Harness actions added:**

- `dump_table_layout {tableIndex, resultPath}` — emits `{col_index, applied_width_pt, natural_width_pt, locked: bool, flex: bool, ellipsized_lines_count: int}`. Lets test drivers assert what the user sees.

**DOD:**

- Open a doc with the Decision-log table from D19 spec. Verify visually + via `dump_table_layout`:
  - Date column ≈ natural width (locked)
  - Decided By column ≈ natural width (locked)
  - Decision column = remainder (flex)
- No more 320pt cap visible: a wide window gives the Decision column full available width.
- Over-long-token cell: ellipsizes per Q8 if window is narrow; full token visible if window is wide enough.
- D17 manual test plan rerun GREEN — basic table rendering, in-place cell editing, click-into-wrapped-cell, scroll-on-edit all still work.

**Commit:** `D24 phase 4 — distribute and apply column widths; cell byTruncatingTail`

---

## Phase 5 — Resize debounce + reflow triggers

**Goal:** Window resize triggers Pass 2 + Pass 3 (cached Pass 1 hits — no remeasure). Debounced per Q3 decision (100ms tail on `NSWindow.didResizeNotification`). Storage edits already invalidate the natural-width cache via phase 2.

**Files updated:**

- `Sources/Workspace/EditorContainer.swift` (or app-level):
  - Subscribe to `NSWindow.didResizeNotification` on the main window.
  - Debounce: store a token; on each notification, cancel the previous and schedule a new 100ms task. On firing, walk all open documents' rendered tables and re-run distribution.
- `Sources/Editor/Renderer/Tables/TK1TableBuilder.swift`:
  - Expose a `redistribute(forContainerWidth: CGFloat)` entry point that re-runs Pass 2 + Pass 3 from the cached natural widths.

**Harness actions added:**

- `set_window_width {pt}` — programmatic window-width resize. Internally calls `NSWindow.setContentSize(_:)`.
- `dump_table_layout` (extended) — already added in phase 4.

**DOD:**

- `set_window_width` followed by `dump_table_layout` shows expected re-distribution.
- Manual: drag-resize the window. Tables reflow smoothly. No jank during the drag (the 100ms debounce holds layout still until the drag eases).
- Storage edit (insert text) → affected table's natural widths recompute immediately; unaffected tables don't.
- Performance: 10-row × 4-col table reflows on resize in < 5ms (cached natural widths; just re-run Pass 2 + Pass 3).

**Commit:** `D24 phase 5 — resize debounce + reflow on window-width change`

---

## Phase 6 — Manual test plan + COMPLETE + roadmap

**Goal:** Close the deliverable.

**Files created:**

- `docs/current_work/testing/d24_responsive_table_columns_manual_test_plan.md` — sections cover: Decision-log shape, narrow viewport, wide viewport, single super-long token, all-flex, all-narrow, empty table, single column, resize-during-edit. Each scenario has a harness-recipe block.
- `docs/current_work/stepwise_results/d24_responsive_table_columns_COMPLETE.md` — completion record per template.

**Files updated:**

- `docs/issues_backlog.md` — i02 status flips to `Fixed (D24, 2026-04-28)`.
- `docs/roadmap_ref.md` — D24 → ✅ Complete; change-log entry.

**DOD:**

- Manual test plan walked end-to-end; results recorded.
- COMPLETE doc references the spec, plan, prompt, manual test plan, and the i02 fix.
- Roadmap reflects D24 ✅; i02 marked Fixed.
- `xcodebuild test` GREEN (carried forward from D18 i03 + new D24 unit tests).

**Commit:** `D24 phase 6 — manual test plan + COMPLETE + roadmap; i02 Fixed`

---

## Risks / open implementation questions

1. **Spike outcome** (phase 1) is the gating risk. If `byTruncatingTail` doesn't behave as Q8 claims, plan diverges to a custom layout-manager hook that detects mid-token line breaks and applies truncation. Estimate: +1 phase if fallback needed.

2. **Cache invalidation under storage edits.** TK1 storage edits arrive as `NSTextStorage.processEditing()` notifications. The cache must invalidate on edits within a table's range, not on edits elsewhere. Anchored on the table's paragraph-style attribute or on a stable AST identifier — see spec risk #4.

3. **Drag-resize visual feel.** 100ms debounce keeps layout still during the drag, but might feel laggy. Possible UX refinements (out of scope for D24): live-update with throttled invalidation; or render columns proportionally to drag delta and rebalance on drag end. Decide based on dogfood feel; D24 ships with the simpler debounce.

4. **`NSTextContainer.containerSize.width` vs scroll view's content width.** If we're wrong about which to use, the layout will be off by the gutter or by the scroll-bar width. Phase 4 verifies against pixel-measurements in the harness.

5. **Anchored cache key.** `table_anchor_range` shifts under storage edits before/after the table. The anchor needs to be a paragraph-style or attribute marker, not a literal `NSRange`. Phase 2 implements; phase 4 stress-tests with multi-edit scenarios.
