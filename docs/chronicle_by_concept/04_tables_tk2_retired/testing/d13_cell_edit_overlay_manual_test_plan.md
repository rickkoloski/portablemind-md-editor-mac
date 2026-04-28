## D13: Cell-Edit Overlay — Manual Test Plan

**Spec:** `docs/current_work/specs/d13_cell_edit_overlay_spec.md`
**Plan:** `docs/current_work/planning/d13_cell_edit_overlay_plan.md`
**Spike:** `spikes/d13_overlay/` (GREEN, reference)
**Created:** 2026-04-26

---

## Setup

```bash
cd ~/src/apps/md-editor-mac
source scripts/env.sh
xcodegen generate
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor -configuration Debug \
           -derivedDataPath ./.build-xcode build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
./scripts/md-editor /tmp/d13-prod-seed.md
```

Use the seed file (the d13 prod test buffer):

```markdown
| A | B |
|---|---|
| one | two |

| Description                         | Status |
|-------------------------------------|--------|
| This is intentionally long enough to wrap across at least two visual lines inside its column. | OK |
| Short                              | Triple-wrap candidate: this content is even longer to push it to three visual lines so the spike can validate clicks beyond line 2. |

| col1 |   | col3 |
|------|---|------|
| a    |   | c    |
```

Save it at `/tmp/d13-prod-seed.md` or open the spike's seed at the same path.

---

## A. Overlay show/commit core

| Test | Action | Expected |
|---|---|---|
| A1 | Single-click in cell `one` | Overlay mounts; 2pt accent border around the cell; caret at click position; cell content visible inside the border |
| A2 | Type characters | Characters appear at caret; overlay text updates |
| A3 | Press Enter (or Return) | Overlay commits; source updates with new cell content; overlay dismisses |
| A4 | Single-click in cell `two`, type `Z`, press Escape | Source for cell B unchanged (Z discarded); overlay dismisses |
| A5 | Click outside the table after typing in an overlay | Commit fires on click-out; source updated; overlay dismissed |

---

## B. Wrapped cell — primary D13 case

| Test | Action | Expected |
|---|---|---|
| B1 | Click on visual line 1 of the wrapped Description cell | Overlay mounts; caret on line 1 at click x |
| B2 | **PRIMARY** — Click on visual line 2 of the same cell | Overlay mounts; caret on line 2 at click x. NOT pinned to line 1; NOT routed to next cell |
| B3 | Click on the third (last) line | Caret on line 3 |
| B4 | Up/Down arrow inside wrapped overlay | Caret moves visual lines naturally |
| B5 | Type past column width (long string) | Content reflows inside overlay; visually may spill past cell height during typing (acceptable Numbers/Excel pattern); on commit, row reflows cleanly |

---

## C. Tab navigation

| Test | Action | Expected |
|---|---|---|
| C1 | In cell `one` (table 0 col 0), press Tab | Overlay moves to cell `two` (col 1) |
| C2 | In cell `two`, press Shift+Tab | Overlay returns to cell `one` |
| C3 | In cell `two`, press Tab past the last cell of the last body row | Overlay dismisses (table boundary) |
| C4 | In wrapped Description body row 0 col 1 (`OK`), press Tab | Overlay opens on next-row col 0 (`Short`) — cross-row advance |
| C5 | In `Short`, press Shift+Tab | Overlay returns to `OK` |
| C6 | In wrapped Description body row 0 col 0 (first body cell), press Shift+Tab | Overlay dismisses (header EXCLUDED from cycle) |

---

## D. Active-cell border affordance (§3.7)

| Test | Action | Expected |
|---|---|---|
| D1 | Activate any cell via single-click | 2pt accent border around the FULL cell (including cellInset gutter) |
| D2 | Compare text position active vs inactive | No shift — text in same coords whether overlay is mounted or not |
| D3 | Click a different cell | Previous border disappears; new cell's border draws |

---

## E. Scroll-while-active

Setup: open a long doc with tables (use `docs/roadmap_ref.md` for a real-world test).

| Test | Action | Expected |
|---|---|---|
| E1 | Click into a table cell, then scroll the document | Overlay commits + dismisses; user must re-click after scroll to edit again |
| E2 | Click into a table cell, then click a different cell | Previous overlay commits, new one mounts |

---

## F. Empty cell

| Test | Action | Expected |
|---|---|---|
| F1 | Click on the empty middle cell of table 2 (between `col1` and `col3`) | Overlay mounts; empty content; caret at offset 0 |
| F2 | Type a character + commit | Source updates; cell now shows the typed character |

---

## G. Modal popout (§3.12)

| Test | Action | Expected |
|---|---|---|
| G1 | Right-click on a cell | Context menu includes "Edit Cell in Popout…" |
| G2 | Select "Edit Cell in Popout…" | Modal window opens centered, ~600x400, titled "Edit Cell — Row N Col M" |
| G3 | Modal shows the cell's source content with `\|` un-escaped to literal `|` | Confirmed |
| G4 | Save (button or ⌘+Return) | Source updates with re-escaped content; modal closes |
| G5 | Cancel (button or Escape) | Source unchanged; modal closes |
| G6 | Open modal, type a literal `|`, save | Source has `\|` (escape applied) |
| G7 | Right-click WHILE overlay is active on the SAME cell | "Edit Cell in Popout…" menu item is OMITTED |

---

## H. Handoff (§3.13)

| Test | Action | Expected |
|---|---|---|
| H1 | Show overlay on cell A, type characters, then right-click cell B → "Edit Cell in Popout…" | Overlay on A commits (typed text persisted); modal opens on B |
| H2 | Open modal on cell A, then click on cell B in the host editor | Click is intercepted by modal session — no effect on host until modal commits/cancels |

---

## I. Reveal mode interaction (D8.1 retained)

| Test | Action | Expected |
|---|---|---|
| I1 | Double-click on a cell | Whole-row drops to source mode (D8.1 D12-retained behavior) |
| I2 | While row is in source-reveal, single-click in that row | Default NSTextView click handling (no overlay) |
| I3 | Click outside the revealed table | Row un-reveals; tables back to grid |

---

## J. Regression checks

| Test | Action | Expected |
|---|---|---|
| J1 | D8 grid rendering — open `docs/roadmap_ref.md` | Tables render as grids |
| J2 | D9 scroll-to-line — `./scripts/md-editor docs/roadmap_ref.md:42` | Caret at line 42 |
| J3 | D10 line numbers — toggle via View menu / Cmd+Opt+L | Line numbers appear/disappear |
| J4 | D11 CLI view-state — `./scripts/md-editor --line-numbers=on` | Line numbers visible |
| J5 | D12 cell-boundary nav — caret in cell A's content; Right Arrow at end | Caret jumps to next cell |
| J6 | D8.1 delimiter reveal — caret on `**bold**` syntax | Asterisks revealed |

---

## K. Engineering standards

```bash
grep -rn '\.layoutManager' Sources/ | grep -v -e '// ' -e '/\*'
```

Expected: returns nothing new beyond pre-D13 baseline (production has 0 references; D13 must not introduce any).

---

## Failure pointers

If any of A1, A3, A4, B1, B2 fail: check `LiveRenderTextView.mouseDown` integration (Phase 3). The single-click → overlay path may not be wired.

If A2/B5 fail: check overlay's NSTextView config (textContainerInset, fontand container size in `CellEditController.showOverlay`).

If C4 (cross-row Tab) fails after recent commit: check `CellEditController.overlayAdvanceTab` anchor logic. The `TableAnchor` capture must happen BEFORE commit().

If C6 (header exclusion) fails: verify `firstBodyRow = 1` and `nextRow >= firstBodyRow` check in overlayAdvanceTab.

If D1/D2 fail visually: check `CellEditController.showOverlay`'s frame computation (incl. cellInset) and `textContainerInset` set to cellInset.

If E1 (scroll-commit) fails: check NSScrollView observer registration in startScrollObserver / teardown's stopScrollObserver.

If G2 (modal opens) fails: check `LiveRenderTextView.menu(for:)` — verify "Edit Cell in Popout…" item is added when click hits a cell.

If G7 (omit on same cell) fails: verify the `controller.activeRow == cci && controller.activeCol == colIdx` check.

If H1 (handoff overlay→modal) fails: check `editCellInPopoutAction` — must commit the active overlay BEFORE opening modal.

If I2 (revealed row no overlay) fails: check `isRowRevealed` in `LiveRenderTextView.mouseDown`.

---

## Graduation to XCUITest

The harness-driven tests in `Sources/Debug/HarnessCommandPoller.swift` are the automated test gate per phase. They cover:
- Phase 1: `query_caret_for_click`
- Phase 2: `show_overlay_at_table_cell`, `type_in_overlay`, `commit_overlay`, `cancel_overlay`
- Phase 3: `simulate_click_at_table_cell`
- Phase 4: `advance_overlay_tab`
- Phase 5: `open_modal_at_table_cell`, `set_modal_text`, `commit_modal`, `cancel_modal`

Future XCUITest could replace the harness with synthetic mouse/key events; the harness exists because synthetic input depends on the app being frontmost (often broken in autonomous test runs). For now, the harness is the canonical regression suite.

Strip via `grep -rn 'TEST-HARNESS:' Sources/` if/when no longer needed.
