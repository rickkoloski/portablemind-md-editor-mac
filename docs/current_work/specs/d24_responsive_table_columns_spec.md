# D24 — Responsive table column layout

**Status:** APPROVED FRAME — all seven open questions resolved up front (see Decision log, 2026-04-28). Plan + prompt next.

**Trace:**
- `docs/vision.md` — Principle 1 (Word/Docs-familiar authoring). Modern editors auto-fit table columns to viewport; ours hard-caps at 320pt regardless of window width, which CD experiences as cramped meaty columns sitting next to wide whitespace.
- `docs/issues_backlog.md` — **resolves i02** (Markdown table column widths capped at 320pt regardless of viewport). Adopts the third proposed fix path from i02's analysis: proportional layout with a `table-layout: auto` shape.
- `docs/engineering-standards_ref.md` §3.1 — branching: lands on `feature/d24-responsive-table-columns`.
- `chronicle_by_concept/05_tables/_index.md` — implementation surface is the current TK1 `NSTextTable` / `NSTextTableBlock` chain (D17 era). The retired TK2 fragment math in `04_tables_tk2_retired` is **not** the implementation surface; this deliverable's column-width logic is plain TK1 paragraph + table-block geometry.

**Position in roadmap:** D24 — quality improvement on top of D17's TK1 table foundation. Independent of D20 (connection-mgmt) and D23+ (PM file mgmt). Resolves a backlog item that's been bothering CD since the D18 spec's Decision log table.

---

## Why now

D17's TK1 migration retired ~3,200 lines of custom layout, but inherited a column-cap heuristic from the D8 TK2 era — a hard 320pt limit per column, originally there to keep extreme content (a paragraph in a single cell) from blowing out the viewport. The cap predates window-aware sizing.

Symptom in dogfood: text-heavy columns (Decision-log-style "what changed" descriptions) wrap aggressively while short-token columns (Date, Decided By) sit in their natural width, leaving most of the window as whitespace next to the cramped column. CD reads PM Markdown's render of D-spec Decision log tables daily; the current behavior makes that experience visibly worse than VS Code's preview of the same source.

A single fix lifts every markdown table in the editor — spec docs, decision logs, comparison tables, all dogfooded daily.

---

## Algorithm

CSS `table-layout: auto` semantics, expressed in terms TK1 can implement.

### Definitions

- **`natural_width(col)`** — the layout width a column would consume if given infinite horizontal space. Measured as the **longest single line** across all cells in the column, after CoreText shaping. Single-line because wrapping is what we're trying to control; the natural width is "the width at which this column wouldn't need to wrap *anything*." **Capped** at `viewport_width` (Decision Q8) — no column claims more space than the viewport could ever give it, even if it contains a single 2000pt-wide URL.
- **`min_width(col)`** — `min(natural_width(col), 60pt)`. The floor below which we refuse to shrink a column. 60pt is the engineering-standard floor; smaller columns turn into one-character-per-line which is unreadable.
- **`viewport_width`** — the available horizontal width inside the editor's text container, minus the table's outer padding/border insets.
- **`fits_naturally(col)`** — true iff `natural_width(col) ≤ proportional_share(col)`.

### Pass 1 — measure

Compute `natural_width(col)` for every column. Cache by `(table_id, col_index, content_hash)` so re-renders without content edits hit the cache.

### Pass 2 — distribute

```
total_natural = Σ natural_width(c) for c in cols
if total_natural ≤ viewport_width:
    # Everything fits. Lock every column to its natural width.
    for c in cols: width(c) = natural_width(c)
    # No wrapping anywhere. (See Decision Q6.)
else:
    # Doesn't all fit. Identify "lock-in" columns whose natural width is
    # less than the equal share — these get their natural width and
    # bow out of the flex pool.
    candidates = cols
    locked = {}
    loop:
        flex_width = viewport_width - Σ width(c) for c in locked
        equal_share = flex_width / |candidates - locked|
        new_locks = { c in candidates - locked : natural_width(c) ≤ equal_share }
        if new_locks is empty: break
        for c in new_locks:
            width(c) = natural_width(c)
            locked.add(c)
    # Remaining (flex) columns share the leftover proportionally to
    # their natural widths.
    flex_cols = candidates - locked
    flex_total_natural = Σ natural_width(c) for c in flex_cols
    flex_pool = viewport_width - Σ width(c) for c in locked
    for c in flex_cols:
        share = (natural_width(c) / flex_total_natural) * flex_pool
        width(c) = max(min_width(c), share)
    # If the min_width floor pushes us over the viewport (only
    # possible when viewport_width < 60pt × num_cols, e.g., absurdly
    # narrow window), reduce proportionally from the flex columns
    # above the floor. Floor wins; rather extend past the viewport
    # than stack one-char-per-line columns. With natural_width capped
    # at viewport_width (Q8), the only way this branch fires is the
    # narrow-viewport case above; super-long tokens no longer push us
    # past viewport.
```

The "lock-in pass" runs until convergence (typically 1-2 iterations even for tables with many narrow columns). It produces the VS Code behavior the screenshots show: short-token columns hug their content, long-text columns split the rest proportionally.

### Pass 3 — apply

Set `NSTextTableBlock` `width` per column. TK1 honors per-block widths in absolute points (not percent) on macOS; the existing `setValue(_:type:for:)` API takes `NSTextBlock.ValueType.absoluteValueType`. No custom layout passes needed beyond what TK1 already does on the storage edit + container resize cycles.

Cell content gets `NSParagraphStyle.lineBreakMode = .byTruncatingTail` (Decision Q8). With multi-line cells (no `numberOfLines` cap), TextKit's behavior is: wrap at word boundaries normally; push an over-long unbreakable token to its own line; if even on its own line the token can't fit, ellipsize the trailing portion (`https://very-long-…`). Subsequent paragraph content below the over-long token continues to wrap normally.

---

## Reflow triggers (Decision Q3 — debounced)

Reflow runs on:
- **Storage edits** (parse-time): a table's content changed, recompute via Pass 1+2+3.
- **Container width change**: debounced by `NSScrollView.willStartLiveScrollNotification` / `didEndLiveScrollNotification` window-resize semantics. During an active resize drag we recompute on `didEndLiveScroll`-equivalent (window resize doesn't emit those, so we use `NSWindow.didResizeNotification` with a 100ms debounce). Cheap but not zero — debounce keeps drag-resize feeling smooth.

Out of scope for D24 reflow:
- Font-size change (no font UI exists yet)
- Line-numbers gutter toggle (the gutter doesn't share width with the text container in the current layout)

---

## Source-mode reveal (Decision Q4 — unconstrained)

D8.1's source-reveal mechanism was retired by D17; in-place TK1 cell editing replaces it. There is no longer a "table → reveal pipe-source" mode in current behavior, so this question is largely moot — but for any future reveal mechanism, the responsive widths apply only to the **rendered grid**, not to a source view. Source mode is plain monospaced markdown text and should not have NSTextTable widths constraining it.

---

## Edge cases

- **Single super-long unbreakable token** in a column (a long URL with no whitespace, base64 blob, etc.) — `natural_width(col)` is **capped at `viewport_width`** (Decision Q8), so the column never claims more than the viewport can give. The cell's paragraph style uses `byTruncatingTail`, so the over-long token gets its own line; if even that line is too narrow, the trailing portion ellipsizes. The table never extends past the viewport's right edge. (Revises Decision Q2.)
- **Many narrow columns + one wide column** — common in our docs. The lock-in pass handles this in one iteration: narrow columns lock first, the wide column gets the remainder.
- **All columns flex** (no narrow ones) — the lock-in pass finds no candidates to lock, falls through to proportional distribution across all columns. Behaves identically to a uniform `table-layout: fixed` only if all natural widths happen to be equal.
- **Empty table** — degenerate; preserve current TK1 default (single empty row, equal-width columns).
- **Single column** — trivially gets `viewport_width` minus padding.
- **Inline images inside a cell** — out of scope for D24 (md-editor doesn't render inline images yet); when added, image intrinsic width participates in `natural_width` calculation.

---

## Performance (Decision Q7 — parse + container cache)

The expensive operation is `natural_width(col)` measurement: a CoreText shaping pass over every cell in the column. Cache invalidation:
- **Parse-time invalidation**: any storage edit affecting a table's range invalidates that table's natural-width cache.
- **Container-width invalidation**: container width is *not* a `natural_width` input (column widths derive from natural widths + viewport, not from natural-width-given-viewport). So container resize re-runs Pass 2+3 from cached Pass-1 data — cheap, no remeasure.
- **Cache key**: `(table_anchor_range, content_hash_of_cells)`. Anchored on the storage range so reused-after-edit lookups still hit when the cell content didn't change.

A 10-row × 4-col table with paragraph-length descriptions measures in single-digit milliseconds. Caching makes the resize path effectively free.

---

## Out of scope (deferred to future deliverables)

- **User-resizable columns** (drag the column boundary). Significant scope: hit-testing, drag UI, persistence per-doc. Worth its own deliverable later.
- **Persistent column-width preference** across sessions for the same doc.
- **Column-width hints in the markdown source** (`| header | --- | header |` with explicit `:---:` alignment is GFM standard, but explicit width hints aren't). Not a markdown feature; not adding non-standard syntax.
- **Inline image intrinsic widths** (md-editor doesn't render images yet).
- **Source-mode revealed table widths** — superseded by D17; in-place editing replaces source-mode reveal.

---

## Acceptance criteria

1. The Decision log table in any spec doc (D18, D19, D24, etc.) renders with the "Decision" column wider than the "Date" / "Decided By" columns, no horizontal whitespace next to the wrapped text.
2. Resizing the editor window narrower causes the Description column to wrap before the short-token columns; resizing wider unwraps it.
3. The two screenshot scenarios CD provided (mid-width and narrow-width) reproduce against the editor — at the wider window, only the longest cells wrap; at the narrower window, all text-heavy columns wrap proportionally.
4. A 10-row × 4-col paragraph-content table measures + lays out in < 50ms on first render and < 5ms on container-resize-only.
5. Manual test plan at `docs/current_work/testing/d24_responsive_table_columns_manual_test_plan.md` covers: narrow viewport, wide viewport, single super-long token, many-narrow + one-wide, all-flex, empty table, single column.
6. Harness verification — extend `dump_state` (or a new `dump_table_layout` action) to surface per-column computed widths so test drivers can assert without screenshot diffing.
7. Regression sweep: D17 manual test plan rerun GREEN — basic table rendering, in-place cell editing, click-into-wrapped-cell, scroll-on-edit (the four canonical D16 scenarios) all still work.

---

## Decision log

| Date | Decision | Decided by |
|---|---|---|
| 2026-04-28 | **Q1 — Algorithm baseline:** content-aware proportional layout. `natural_width = longest unbreakable token`; columns with `natural_width ≤ proportional_share` lock at natural; remaining flex columns share leftover viewport proportionally to their natural widths. Wrapping only when proportional share < natural width. Mirrors VS Code preview semantics + browser `table-layout: auto`. | RAK |
| 2026-04-28 | **Q2 — Minimum column width floor:** `min(natural_width, 60pt)`. Below 60pt a column degrades to one-char-per-line and becomes unreadable; we'd rather extend past the viewport's right edge than collapse a column to glyph-width. | RAK |
| 2026-04-28 | **Q3 — Reflow trigger:** debounced. Storage edits reflow synchronously at parse time. Container width changes debounce on `NSWindow.didResizeNotification` with a 100ms tail. No reflow on font-size or line-numbers-gutter changes (out of scope). | RAK |
| 2026-04-28 | **Q4 — Source-mode reveal:** unconstrained. The retired D8.1 reveal mechanism was replaced by D17's in-place editing; no current source-reveal mode exists. Any future reveal mechanism leaves the source view as plain monospaced text — responsive widths apply only to the rendered grid. | RAK |
| 2026-04-28 | **Q5 — Header vs body rows:** same algorithm, no special-casing for the header. The header participates in `natural_width` measurement like any other row. | RAK |
| 2026-04-28 | **Q6 — Single-line-cell preference:** prefer single-line until forced to wrap. When `total_natural ≤ viewport_width`, every column locks to its natural width — no wrapping anywhere. The proportional distribution kicks in only when the viewport can't accommodate everyone's natural width. Matches VS Code; matches reader expectation that "wider window means less wrap, not just bigger gaps." | RAK |
| 2026-04-28 | **Q7 — Caching:** measure-cache keyed on `(table_anchor_range, content_hash_of_cells)`. Pass 1 (`natural_width` measurement) is cached; Pass 2+3 (distribute + apply) re-run on container-width change. Storage edits invalidate the affected table's cache; nothing else does. | RAK |
| 2026-04-28 | **Q8 — Super-long-token handling (revises Q2):** instead of allowing a column with a single super-long token to claim its full natural width and force the table past the viewport's right edge, **cap `natural_width(col)` at `viewport_width`** and use `NSLineBreakMode.byTruncatingTail` on cell paragraph style. TextKit's out-of-the-box behavior with no `numberOfLines` cap is: wrap at word boundaries normally; over-long unbreakable tokens get pushed to their own line; if even on their own line the token can't fit, the trailing portion ellipsizes. The table never extends past the viewport. Removes the "table-extends-past-viewport" branch from Pass 2 — algorithm gets simpler. | RAK |

---

## Risks / open implementation questions

1. **TK1 `NSTextTableBlock.width` units.** TK1 historically supports `absoluteValueType` and `percentageValueType` on text-block widths. We use absolute points (the algorithm computes points). Cross-check with Apple's TextEdit behavior to make sure absolute widths reflow correctly on container resize without jitter.

2. **Container-width source-of-truth.** `NSTextContainer.containerSize.width` is the layout-time width; the scroll view's `contentSize.width` is the geometry-time width. Pick one — almost certainly `containerSize.width` since that's what `NSTextTableBlock` measures against during layout.

3. **Resize-during-edit interaction.** If the user is mid-edit in a cell when the window resizes, do we keep the caret stable? TK1's reflow already preserves caret position; verify there's no regression with our additional column-width recompute.

4. **Anchored cache invalidation.** `table_anchor_range` shifts under storage edits before/after the table. The anchor needs to be a paragraph-style or attribute marker, not a literal `NSRange` — a literal range would invalidate spuriously on every edit elsewhere in the doc.

5. **Test fixture.** A sample markdown doc with the four canonical layouts (Decision log style, narrow-status, all-flex, single-super-long-token) lives in `spikes/` or similar — referenced by the manual test plan. Author it as part of phase 1.

6. **Verify `byTruncatingTail` behavior on multi-line cells (Q8).** The spec claims TextKit with `lineBreakMode = .byTruncatingTail` and no `numberOfLines` cap will wrap at word boundaries normally, push over-long tokens to their own line, and ellipsize only when an unbreakable token can't fit on a single line. Apple's NSLineBreakMode docs are imprecise about the multi-line case; phase 1 must validate this in a small spike before the algorithm commits to it. **Fallback if behavior differs:** explicit per-cell truncation via a custom NSLayoutManager hook that detects mid-token line breaks.
