# D8.1: Table Reveal — Manual Test Plan

**Deliverable:** D8.1 — Table reveal on caret-in-range
**Triad:** `specs/d08_1_table_reveal_spec.md` · `planning/d08_1_table_reveal_plan.md` · `prompts/d08_1_table_reveal_prompt.md`
**COMPLETE:** `stepwise_results/d08_1_table_reveal_COMPLETE.md`
**Created:** 2026-04-24

---

## Purpose

Bridge validation artifact between "build green" and future automated UI tests. Exercises the user-visible behaviors D8.1 added plus the findings captured during implementation, so any regression shows up as a failing step with a concrete cause pointer. When this eventually graduates to XCUITest, each section below becomes a test method with the same name.

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
./scripts/md-editor docs/roadmap_ref.md
```

Expect the roadmap table rendered as a grid (D8 behavior, unchanged).

---

## Section A — Core reveal

| Step | Action | Expected |
|---|---|---|
| A1 | Click anywhere on the roadmap grid (any row, any column). | Whole table flips to pipe-source (`\| D1 \| TextKit 2 ... \|`). Caret lands where you clicked. |
| A2 | Arrow-Down past the last row. | Grid returns. |
| A3 | Arrow-Up back into the table. | Source returns. |
| A4 | Click outside the table (blank line or another paragraph). | Grid returns. |

**Failure pointer:** A1 failing to place a caret → **Finding #2 regression** (paragraph-style min/max line height / hit-testing). Check `MarkdownRenderer.visitTable` still attaches `.paragraphStyle` with `minimumLineHeight == maximumLineHeight == row grid height`.

## Section B — Edit round-trip

| Step | Action | Expected |
|---|---|---|
| B1 | Click into the Status cell of the D8 row (currently `✅ Complete — 2026-04-23 (grid rendering; D8.1 ships reveal-on-caret)`). | Source visible, caret in the cell. |
| B2 | Delete `(grid rendering; D8.1 ships reveal-on-caret)` and type `(ready)`. | Text updates live. Grid re-computes on each keystroke — expected brief redraw, should not visually "blink" the whole table. |
| B3 | Arrow out of the table (down past last row). | Grid returns with the edit reflected in the Status cell. |
| B4 | Cmd-Z. | Edit reverts. |
| B5 | Cmd-S, close the tab, reopen via `./scripts/md-editor docs/roadmap_ref.md`. | On-disk file matches what was saved. If you undid everything and saved, content unchanged; if you saved the edit, grid shows the edit. |

**Failure pointer:** B3 producing a blank or stale grid → **Finding #4 regression** (stale `TableLayout` identity after re-render). Check `Coordinator.findTableRange(for:in:)` correctly re-resolves the current layout via attribute scan.

## Section C — Multi-table independence

```bash
./scripts/md-editor docs/competitive-analysis.md
```

This doc has multiple tables.

| Step | Action | Expected |
|---|---|---|
| C1 | Click into the first table. | Table 1 reveals, others stay gridded. |
| C2 | Click into the second table (no intermediate out-of-table clicks). | Table 1 returns to grid, Table 2 reveals. |
| C3 | Arrow-Up/Down through text between the tables. | Reveal toggles off as caret enters the between-tables paragraph. |

**Failure pointer:** C2 leaving both tables revealed → `revealedTableLayoutID` diffing logic in `updateTableReveal` not removing the old ID.

## Section D — Edge cases

| Step | Action | Expected |
|---|---|---|
| D1 | Click on the header row (topmost row of a table). | Whole table reveals — header is a row. |
| D2 | Click in the last body row near the bottom border. | Reveal triggers, caret lands. |
| D3 | Cmd+A inside a revealed table. | Full-document select, table's pipe source highlighted. No crash. |
| D4 | Click-and-drag from above the table, across it, to below. | Selection spans the three regions. Table reveals while caret-end is inside; grid returns when the caret-end lands outside. |
| D5 | Backspace at column 0 of the header row (before the leading `\|`). | The preceding paragraph's last char is consumed. No crash. (Editing *into* the pipe source is intentionally ugly — backlog task **#1386** addresses per-cell editing.) |

## Section E — Regression checks (other deliverables)

| Step | Action | Expected |
|---|---|---|
| E1 | In `roadmap_ref.md`, click on a `# heading` line. | Delimiter reveal (`#` visible) — **CursorLineTracker** still runs alongside table reveal. |
| E2 | `./scripts/md-editor docs/roadmap_ref.md:20`. | Opens scrolled to line 20 (**D9**). |
| E3 | View menu → Show Line Numbers (or Cmd+Opt+L). | Line numbers toggle (**D10**). |
| E4 | `./scripts/md-editor --line-numbers=on docs/roadmap_ref.md`; quit; reopen without flag. | Line numbers persisted via AppSettings (**D11**). |

## Section F — Engineering standards

```bash
grep -rn '\.layoutManager' Sources/
```

Only the four existing docstring warnings should appear. Any new production reference = **§2.2 violation**.

---

## Findings capture template

If any step fails:

```
Step: <ID>
Expected: <from table>
Observed: <what actually happened>
Reproduces: consistently | intermittently | once
Console: <paste any NSLog / console output>
Suspect: <code pointer — which function/file>
```

File findings against the deliverable in `docs/current_work/issues/` if they block shipping, or against Harmoniq project #53 if they're backlog-grade.

---

## Graduation to automated tests

When this plan is ported to XCUITest (or Playwright-equivalent for a web port):

- Each **Section** becomes a test class (e.g., `TableRevealCoreTests`, `TableRevealEditRoundTripTests`).
- Each numbered **Step** becomes a test method.
- **Failure pointers** become assertion messages so a CI failure says "Finding #2 regression — check paragraph-style hit-testing" instead of just "click failed."
- Fixture files: copies of `roadmap_ref.md` and `competitive-analysis.md` checked into `UITests/Fixtures/` so tests don't depend on live doc content.
- The file itself stays — manual test plans remain a first-class SDLC artifact. Automation is a layer *on top of* manual, not a replacement.
