# D12: Per-Cell Table Editing — Manual Test Plan

**Deliverable:** D12 — Per-cell table editing
**Triad:** `specs/d12_per_cell_table_editing_spec.md` · `planning/d12_per_cell_table_editing_plan.md` · `prompts/d12_per_cell_table_editing_prompt.md`
**Spike findings reference:** `spikes/d12_cell_caret/STATUS.md`
**COMPLETE:** `stepwise_results/d12_per_cell_table_editing_COMPLETE.md`
**Created:** 2026-04-25

---

## Purpose

Validation contract for D12. Each tier mirrors the spike's tier structure — the same architectural questions answered there are re-validated here against the production codebase. Failures map back to specific files and line ranges via the "Failure pointers" sections.

When this graduates to XCUITest, each numbered step becomes a test method; the harness's `set_selection`, `dump_state`, `snapshot`, `cell_screen_rects`, `set_text` actions become test fixtures.

## Setup

```bash
cd ~/src/apps/md-editor-mac
source scripts/env.sh
xcodegen generate
xcodebuild -project MdEditor.xcodeproj \
           -scheme MdEditor \
           -configuration Debug \
           -derivedDataPath ./.build-xcode \
           build
open .build-xcode/Build/Products/Debug/MdEditor.app
```

Open `docs/roadmap_ref.md` (it has a 3-column table with header + body rows) — either via the **File → Open** menu or:

```bash
open "md-editor://open?path=$HOME/src/apps/md-editor-mac/docs/roadmap_ref.md"
```

The harness (Sources/Debug/HarnessCommandPoller.swift, `#if DEBUG`) is alive on launch — `tail -f /var/log/system.log | grep MdEditor` to watch its NSLog output, or use the harness's `dump_state` / `snapshot` actions directly.

---

## Section A — Single-click cell-aware caret placement

| Step | Action | Expected |
|---|---|---|
| A1 | Click anywhere inside a body cell of the roadmap table. | Caret lands at a source offset INSIDE that cell's content range (verifiable via the harness `dump_state` → `selection.location` falls within a cell from `tables[0].cellRanges`). Grid stays rendered (NOT in source-reveal mode). |
| A2 | Click on the white area between two cells (in the small pipe-divider gap). | Caret snaps to the nearest cell edge; does NOT land in the pipe character or whitespace. |
| A3 | Click well past the last character of a cell's content (right end of the cell box). | Caret lands at the cell's content-end offset (one past the last char), NOT at the natural CT-layout offset that would be outside the cell. |

**Failure pointer:** A1 failing means `CellSelectionDataSource.lineFragmentRangeForPoint` isn't being consulted; check `EditorContainer.swift` line ~68 wires the data source via `tlm.textSelectionNavigation`. A2/A3 failing means `LiveRenderTextView.snapCaretToCellContent` isn't running after `super.mouseDown`.

## Section B — Keyboard navigation across cells

| Step | Action | Expected |
|---|---|---|
| B1 | Click in the first cell of any row. Press **Tab**. | Caret jumps to the start of the next cell in the same row (verify via harness `dump_state` → `selection.location` matches `cells[curIdx + 1].location`). |
| B2 | Continue pressing **Tab** through all cells of a row, then once more. | Caret moves to the first cell of the NEXT row (cross-row Tab). |
| B3 | Press **Shift+Tab** at the start of a row's first cell. | Caret jumps to the END of the previous row's last cell (cross-row Shift+Tab). |
| B4 | With caret at a cell's content-end, press **Right Arrow**. | Caret jumps to the next cell's content-start (skipping pipe + whitespace source chars). |
| B5 | With caret at a cell's content-start, press **Left Arrow**. | Caret jumps to the previous cell's content-end (skipping pipe + whitespace source chars). |
| B6 | With caret at the last cell of the last row, press **Right Arrow**. | Caret stays put (boundary). |
| B7 | With caret at the first cell of the first row, press **Left Arrow**. | Caret stays put (boundary). |

**Failure pointer:** any B step failing means the keyDown override in `LiveRenderTextView` isn't triggering; check the override fires (TEST-HARNESS log shows `[CELL-NAV] keyDown ...`) and that `currentTableRow()` returns non-nil.

## Section C — Cell-boundary destructive operations

| Step | Action | Expected |
|---|---|---|
| C1 | Position caret at start of a cell's content (e.g., row-2 cell-1 start). Press **Backspace**. | Caret moves to previous cell's content-end. **Source length unchanged** (no pipe deletion). |
| C2 | From C1's resulting position, press **Backspace** again. | Now in the previous cell's content; backspace deletes the last char of that cell normally. Source length decreases by 1. |
| C3 | Position caret at end of a cell's content. Press **Delete** (forward). | Caret moves to next cell's content-start. Source length unchanged. |
| C4 | At end of the last cell of the last row, press **Delete**. | Boundary — caret stays, no deletion. |

**Failure pointer:** C1/C3 source-length changing means `LiveRenderTextView.deleteBackward`/`deleteForward` cell-boundary protection isn't firing.

## Section D — Double-click reveal (whole-row source mode)

| Step | Action | Expected |
|---|---|---|
| D1 | Double-click any cell in the table. | The whole table drops to pipe-source mode — `\| cell content \|` visible as raw markdown source for ALL rows of that table. |
| D2 | Click outside the table (on body text). | Table returns to grid rendering. |
| D3 | Single-click on a different cell. | Caret moves to that cell. Grid stays rendered (single-click does NOT reveal). |
| D4 | With a doc containing TWO tables, double-click in table A, then single-click in body text, then double-click in table B. | Table A reveals → un-reveals on body click → Table B reveals (independent). |

**Failure pointer:** D3 failing (single-click reveals) means `EditorContainer.Coordinator.updateTableReveal` still has the auto-reveal-on-enter path; should only handle un-reveal-on-leave.

## Section E — Selection highlights

| Step | Action | Expected |
|---|---|---|
| E1 | Drag-select within a cell (or use harness `set_selection` with location/length inside one cell's range). | Selection rendered as a highlight rectangle constrained to the cell, behind the cell content text. |
| E2 | Select across cells within a row (e.g., last 3 chars of cell A through first 3 chars of cell B). | Two SEPARATE highlight rectangles — one for each cell's intersection with the selection. The pipe / whitespace gap between cells is NOT highlighted. |
| E3 | Select across rows (e.g., end of row 1's last cell through start of row 2's first cell). | Per-cell highlights in each row's affected cells. Inter-row source (pipe + newline + pipe) is not highlighted (acceptable: any default NSTextView highlight there is suppressed by per-cell rendering). |

**Failure pointer:** E1 failing (no highlight visible) means `TableRowFragment.drawSelectionHighlights` isn't running or is layered above text. Selection rendering in pipe gap means the row-local-vs-absolute coord shift isn't happening (compare to spike Tier 5 finding).

## Section F — Edit round-trip

| Step | Action | Expected |
|---|---|---|
| F1 | Click in a cell. Type 5 chars. | Source updates: chars inserted at the cell's source range. Cell re-renders with new content. Caret remains visually inside the cell. |
| F2 | Click in another cell. Type 3 chars. | Inserts in THAT cell's range, not the previously-edited one. |
| F3 | Cmd+Z (undo). | Last edit undone. |
| F4 | Cmd+S (save). Close + reopen the doc. | Saved content reflects edits. |

**Failure pointer:** F1 chars going into the WRONG cell means `lineFragmentRangeForPoint` is off; check `cellIndex(forPointX:layout:)` returns the right column.

## Section G — Regression checks

| Step | Action | Expected |
|---|---|---|
| G1 | Open `docs/roadmap_ref.md`. | Grid renders correctly with 3 columns × N rows (D8 unchanged). |
| G2 | Heading delimiter reveal: click on a `# heading` line. | `#` becomes visible (CursorLineTracker still fires; D8 not regressed). |
| G3 | `./scripts/md-editor docs/roadmap_ref.md:20`. | Opens scrolled to line 20 (D9). |
| G4 | `View → Show Line Numbers`. | Line numbers toggle (D10). |
| G5 | `--line-numbers=on/off` CLI flag. | Persists via AppSettings (D11). |

## Section H — Engineering standards

```bash
grep -rn '\.layoutManager' Sources/
```

Should only return docstring warnings — no new production references. Same as before D12 (§2.2 unchanged).

---

## Findings capture template

```
Step: <ID>
Expected: <from table>
Observed: <what actually happened>
Reproduces: consistently | intermittently | once
Harness state: paste relevant /tmp/mdeditor-state.json snippet
Snapshot: /tmp/mdeditor-shot.png  (attach if relevant)
Suspect: <code pointer — file, line, function>
```

---

## Graduation to automated tests

When this plan is ported to XCUITest:

- Each Section becomes a test class.
- Each numbered step becomes a test method.
- Failure pointers become assertion messages.
- Harness actions (`set_selection`, `dump_state`, `snapshot`, `cell_screen_rects`) become test fixtures — already available `#if DEBUG`, just wire to XCUI's `XCTUIApplication`.
- This file stays — manual test plans remain a first-class SDLC artifact alongside automation.
