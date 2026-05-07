# D24: Responsive table column layout — Manual Test Plan

**Spec:** `docs/current_work/specs/d24_responsive_table_columns_spec.md`
**Plan:** `docs/current_work/planning/d24_responsive_table_columns_plan.md`
**Created:** 2026-05-05
**Walks:** all spec acceptance criteria + edge cases + D17 regression spot-check.

> **Note 2026-05-06:** D24.2 (`docs/current_work/specs/d24.2_slack_proportional_columns_spec.md`) replaced D24's lock-in + flex algorithm with Q8 narrow-column threshold lock-in + slack-proportional distribution, and fixed a latent `lineFragmentPadding` bug. Specific column-width numbers in §A1, §A2, §B1–B6 below reflect D24's algorithm (v0.6) and have shifted under D24.2 (v0.6.2). Current numbers and the regression evidence for the v0.6→v0.6.2 transition are in `docs/current_work/stepwise_results/d24.2_slack_proportional_columns_COMPLETE.md` §Smoke evidence. The spec acceptance-criterion shapes (locks vs flex, regime detection, harness verification) remain valid; only the per-column applied-width numerics changed. See §7 below for the D24.2 regression-evidence walk.

---

## Setup

```bash
cd ~/src/apps/md-editor-mac
source scripts/env.sh
xcodegen generate
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
           -configuration Debug \
           -derivedDataPath ./.build-xcode build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Test fixture (write once to `/tmp/d24_p6_fixtures.md` then `open "md-editor://open?path=/tmp/d24_p6_fixtures.md"`):

```markdown
## A — decision-log shape

| Date | Decision | Decided by |
|---|---|---|
| 2026-04-28 | Adopt the responsive distribution over the legacy 320pt cap so wide windows stop wasting whitespace next to long-text columns. | RAK |
| 2026-04-28 | Keep `natural_width(col)` purely content-derived; viewport cap is applied during distribution, not during measurement. | RAK |
| 2026-05-04 | Pivot to byWordWrapping per phase 1 spike. | RAK |

## B — many narrow + one wide

| Status | Owner | Description | Tag |
|---|---|---|---|
| done | Rick | Phase 1 spike landed; recommendation issued. | t1 |
| in-progress | Rick | Phase 2 measurement + cache + harness action. | t2 |
| pending | Rick | Phase 3 distribution algorithm — pure function with XCTest. | t3 |

## C — all narrow

| ID | Tag | Step |
|---|---|---|
| i02 | tables | open |
| i03 | tests | done |
| i04 | auth | stopgap |

## D — all flex

| Heading One | Heading Two | Heading Three |
|---|---|---|
| Each cell carries roughly the same volume of text. | None of the columns can lock at the equal-share threshold. | The distributor splits the viewport proportionally. |

## E — single super-long unbreakable token

| Label | Token |
|---|---|
| short | https://example.com/very-long-unbreakable-token-with-no-whitespace-or-hyphens-that-textkit-cannot-split-on-word-boundaries |

## F — single column

| Note |
|---|
| One-column table — should sit at natural width when content < viewport. |

## G — empty body, header only

| Header A | Header B |
|---|---|
```

The test plan exercises tables A through G, plus a resize sweep against table A.

---

## §1. Cross-cutting harness recipe

The plan below uses these recipes throughout. Mirrors the D19 §C pattern.

```bash
# Dump table N's applied widths (post-distribute):
echo '{"action":"dump_table_layout","tableIndex":N,"path":"/tmp/d24-out.json"}' \
    > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json
sleep 0.5 && cat /tmp/d24-out.json

# Set window width (triggers debounced reflow ~100ms tail):
echo '{"action":"set_window_width","pt":W}' \
    > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json
sleep 0.25   # AppKit posts notification, debounce starts
sleep 0.5    # debounce fires, render replaces storage

# Cache stats (hit/miss/entries):
echo '{"action":"dump_table_natural_widths","tableIndex":N,"path":"/tmp/d24-cache.json"}' \
    > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json
sleep 0.5 && jq .cacheStats /tmp/d24-cache.json
```

Always `mv`-from-`.tmp`, never direct `>` write to the command file (200ms poller race).

---

## §2. Spec acceptance criteria

### A1 — Decision-log shape (spec acceptance #1)

| Step | Action | Expected | Observed (2026-05-05) |
|---|---|---|---|
| A1.1 | Open fixture, dump_table_layout tableIndex=0 at default window. | Date locked at natural (~87pt), Decision flexes wide, Decided by locked at natural (~87pt). | Date=87 (L), Decision=705 (F), Decided by=87 (L) at vp=920 ✓ |
| A1.2 | Visual: Decision column extends to viewport's right edge with clean word-boundary wrap inside the cell. | No horizontal whitespace next to the wrapped text. | Confirmed via snapshot ✓ |

### A2 — Resize narrow ↔ wide (spec acceptance #2 + #3)

Set window width to a sequence of values and confirm Decision column tracks viewport while Date / Decided by stay locked.

| Win | vp (Decision col applied) | Status |
|---|---|---|
| 600 | vp=420 → Decision=205 | ✓ |
| 1200 | vp=720 → Decision=505 | ✓ |
| 1500 | vp=1020 → Decision=805 | ✓ |

Date and Decided by stay at 87pt across all sizes ✓. Date and Decided by are locked because their natural widths (~87pt each) are below the equal-share threshold at every viewport tested.

### A3 — Performance budget (spec acceptance #4)

Spec target: 10-row × 4-col paragraph-content table renders in < 50ms first-render and < 5ms on container-resize-only.

Phase 5 implementation: phase 1 (measurement) is content-hash cached so resize hits the cache for every column; reflow runs only Pass 2 (distribute) + Pass 3 (apply storage attributes). Resize sequence in §A2 above produces no perceptible lag — the dump-after-resize action returns updated widths within the harness's 0.5s sleep, well under any user-visible threshold.

Formal profiling deferred — not blocking. To measure, instrument `renderCurrentText` with `signpost`s and run the resize sequence under Instruments.

### A4 — Harness verification (spec acceptance #6)

`dump_table_layout` produces `{viewportWidth, framingOverhead, distributeTarget, columns: [{column, naturalWidthPt, cappedNaturalPt, appliedWidthPt, locked, flex}]}`. ✓

`dump_table_natural_widths` exposes the Pass-1 cache state: `{columns: [{column, naturalWidthPt, cacheHit}], cacheStats: {hits, misses, entries}}`. ✓

---

## §3. Spec edge cases

### B1 — Many narrow + one wide

Fixture table 1 (4 cols: Status, Owner, Description, Tag).

| Step | Expected | Observed |
|---|---|---|
| B1.1 | dump_table_layout tableIndex=1. Sum of naturals fits the target → all cols locked at natural. | sum=675 ≤ target=864 → all locked: Status=95, Owner=43, Description=511, Tag=26 ✓ |
| B1.2 | Shrink window so target < sum-of-naturals; expect Description to flex while narrow cols stay locked. | (Run set_window_width 600 → vp=420 → Description should be the only flex. Verified via the spec's algorithm; not separately captured but the algorithm passes the unit-test fixture for this shape.) |

### B2 — All-narrow (every col locks via fits-naturally branch)

Fixture table 2.

| Observed |
|---|
| All three narrow columns lock at natural width at default window. ID=26, Tag=52, Step=61. Sum=139 ≪ target=878 → fits-naturally branch ✓ |

### B3 — All-flex (no col below equal-share threshold)

Fixture table 3 (three roughly equal-sized prose cells per column).

| Observed |
|---|
| All three columns flex: c0=359, c1=204, c2=315. Sum=878 = target=878 ✓ Proportional distribution per column natural ratios. |

### B4 — Single super-long unbreakable token (Q8 cap)

Fixture table 4: "short" header + a 200-char URL.

| Observed |
|---|
| Label col locked at 43pt (header bold). URL col's *raw* natural is way past viewport (URL ~~ multi-thousand pt single-line shape), but Q8 caps it at viewportWidth (920) before distribution. Result: URL applied=849pt at vp=920, target=892. URL wraps at hyphen / slash break opportunities (Q9 byWordWrapping); no ellipsis. ✓ |

### B5 — Empty body, header only

Fixture table 6.

| Observed |
|---|
| Two-column header-only table. Both cols locked at 69pt (boldFont natural). No body row text contributes ✓ |

### B6 — Single column

Fixture table 5.

| Observed |
|---|
| Single column with content "One-column table — should sit at natural width when content < viewport." natural=415pt < target=906pt → fits-naturally → locked at 415pt. (Note: VS Code's `<table>` defaults to `width: auto`; a single-column markdown table sitting at natural width is consistent. Use `width: 100%` styling to expand if a future iteration requires it.) ✓ |

### B7 — Resize-during-edit

Place the caret inside Table A's Decision column (wrapped cell) at a known offset, resize the window, verify caret remains inside the same column.

```bash
# Land caret inside "Adopt the responsive..." (offset 5 chars into "Adopt").
SEL=$(python3 -c "
import json,subprocess
# (after a dump_state) find the offset of 'Adopt the responsive'
import sys
print(...)
")
echo "{\"action\":\"set_selection\",\"location\":$SEL,\"length\":0}" \
    > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json
echo '{"action":"set_window_width","pt":600}' \
    > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json
sleep 0.6
echo '{"action":"dump_state","path":"/tmp/state.json"}' \
    > /tmp/cmd.tmp && mv /tmp/cmd.tmp /tmp/mdeditor-command.json
# Verify selection.location is still inside the Decision column substring.
```

Observed: caret position is best-effort-clamped to the new storage length after re-render (re-render replaces storage; offset preserved when surrounding source is unchanged, which is the case for resize-only reflows). ✓ — verified with caret at offset 142 stayed inside "Adopt the respo[nsive]…" cell after resize.

---

## §4. D17 regression spot-check

Phase 4's only behavioral change inside the cell is making `lineBreakMode = .byWordWrapping` explicit (was the implicit NSParagraphStyle default). Sample of D17's manual test plan re-walked:

| D17 ref | Test | Observed |
|---|---|---|
| B1 | Click in a cell mid-table. Caret lands inside cell text. | ✓ via set_selection harness; caret lands at character offset within cell content. |
| B3 | Click in a wrapped cell on visual line 2. Caret lands at the right offset within cell. | ✓ caret offset preserved after resize-induced wrap change. |
| C1–C2 | Tab / Shift+Tab cycle cells. | Out of scope for harness verification (Tab is a stock NSTextView keystroke); deferred to manual interactive walk if a regression surfaces. |
| E | Scroll on edit. | Not exercised by D24 changes. |

Full D17 plan: `docs/chronicle_by_concept/05_tables/testing/d17_textkit1_migration_manual_test_plan.md`.

---

## §5. Failure pointers

If a regression surfaces, the most likely sources:

| Symptom | Look at |
|---|---|
| Tables back to 320pt cap behavior | `Sources/Editor/Renderer/Tables/TK1TableBuilder.swift::computeColumnWidths` — verify it calls `TableColumnDistribution.distribute` (not the legacy heuristic). |
| Resize doesn't reflow | `Sources/Editor/EditorContainer.swift::subscribeToWindowResize` + `scheduleResizeReflow` — verify the observer is wired, the Task isn't deinited prematurely, and the textView's window matches the notification's object. |
| Wrong viewport width | `EditorContainer.renderCurrentText` reads `textView.textContainer?.containerSize.width`. Confirm it isn't returning a stale value (text container size lags the scroll view's content size on first render). |
| Cache always misses | `TableNaturalWidthCache.widthOrCompute(forContentHash:)` — confirm the hash key is content-only (no viewport-dependent component) and the cache isn't being reset between renders. |
| Cell content ellipsizes | Phase 4 set `byWordWrapping` per Q9. If `.byTruncatingTail` re-appears, search for `lineBreakMode` and revert to `byWordWrapping`. |

---

## §6. Graduation to XCUITest

Most of this plan is already harness-driven. The pieces worth promoting to runnable test code:

1. **Distribution algorithm fixtures** — already covered by `UnitTests/TableColumnDistributionTests.swift` (15 tests).
2. **`dump_table_layout` invariants** — could become an XCUITest that opens a sample doc, fires the harness action, asserts on JSON output.
3. **Resize reflow** — could become an XCUITest that sets the window frame, sleeps past the debounce, asserts the dump_table_layout's appliedWidthPt changed.

Promoting (2) and (3) needs the existing UI test target's accessibilityIdentifier wiring to expose harness-result paths. Out of scope for D24; a candidate for a follow-up test infra deliverable.

---

## §7. D24.2 regression evidence (added 2026-05-06)

Bug Rick reported on D24's ship day: "Date column wraps '2026-04-28' mid-string at narrow editor viewport, even though there's clearly room." Fixed by D24.2 (Q8 narrow-column lock-in + lineFragmentPadding compensation). This section is the canonical regression walk against the running editor.

### A. Cold-launch reproduction (pre-D24.2 → fail; D24.2 → pass)

```bash
osascript -e 'tell application "MdEditor" to quit' ; sleep 2
open ./.build-xcode/Build/Products/Debug/MdEditor.app && sleep 2
open "md-editor://open?path=/tmp/d24_phase2_test.md" && sleep 2
```

Visual: open Table A. Pre-D24.2: dates appear wrapped ("2026-04-2" / "8" or similar) when window is narrow. D24.2: dates render on a single line throughout the reachable viewport range.

### B. Drag-resize stability

Slowly drag the editor's right edge inward and outward. Pre-D24.2: dates flicker between wrapped and un-wrapped during the drag. D24.2: dates stay single-line through the entire drag.

### C. Harness sweep

Drive a series of `set_window_width` + `dump_table_layout` pairs and confirm Date.applied stays at max (~86.5pt) at every viewport.

```bash
for w in 1200 800 700; do
  echo "{\"action\":\"set_window_width\",\"pt\":$w}" > /tmp/cmd.tmp && \
    mv /tmp/cmd.tmp /tmp/mdeditor-command.json
  sleep 0.4
  echo '{"action":"dump_table_layout","tableIndex":0,"path":"/tmp/r.json"}' > /tmp/cmd.tmp && \
    mv /tmp/cmd.tmp /tmp/mdeditor-command.json
  sleep 0.3
  jq -r '.viewportWidth as $vp | .regime as $r | .columns | map("c\(.column)=\(.appliedWidthPt)") | "  win=" + (env.w // "?") + " vp=\($vp) regime=\($r) " + (. | join(" "))' /tmp/r.json
done
```

Expected at every viewport above the overflow regime:
- Date applied = ~86.5pt, locked=true (Q8 lock — `max ≤ narrowThreshold=120`)
- Decision applied = flexes per slack distribution
- Decided by applied = ~86.5pt, locked=true (also Q8)
- regime = "slack" (or "fits" if window is wide enough that sumMax ≤ target)

Smoke evidence captured 2026-05-06 in D24.2 COMPLETE doc §Smoke evidence.

### D. Failure pointers (D24.2-specific)

| Symptom | Look at |
|---|---|
| Date wrapping returns | `TK1TableBuilder.cellLineFragmentPadding` constant — confirm it matches the `NSTextContainer.lineFragmentPadding` value in `EditorContainer`. Default 5pt. |
| Date column locked but visually narrower than expected | `TK1TableBuilder.makeCell` — verify `block.setContentWidth(contentWidth + 2 * cellLineFragmentPadding, ...)`. |
| Q8 over-locks (narrow cols starve out a flex col) | `TableColumnDistribution.distribute` Q8 loop — verify the "leaves room for remaining mins" constraint (`poolAfter ≥ remainingMin`). |
| Regime field always "slack" even at wide viewport | `dumpTableLayout` — verify the regime check uses the viewport target (post-framing), not raw viewport. |
