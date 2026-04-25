# D12 Spike — Session Status

**Last updated:** 2026-04-24 (venue switch)
**Phase:** Phase 1 spike, extended into iterative refinement per CD direction: "continue to refine and test in this sandbox and get as many practical cases covered here in isolation before merging back to the main app."

---

## Where we are

**Spike v2 shipped a full round-trip GREEN result:**

- Custom `NSTextLayoutManagerDelegate` returns `CellGridFragment` for the row paragraph.
- `CellGridFragment` draws a two-cell grid (yellow fill, red border, cell content text).
- Custom `NSTextSelectionDataSource` (installed via replaced `NSTextSelectionNavigation`) overrides:
  - `enumerateCaretOffsetsInLineFragment` — maps source offsets inside a cell to x-positions inside the cell's visual bounds.
  - `lineFragmentRangeForPoint` — maps clicks inside a cell's visual rect to that cell's source range.
- Verified observationally by CD:
  - Click into cell 1 → caret inside cell 1 at the clicked x.
  - Type `x` → source updates (`cell one` → `cellx one`), grid re-renders, caret advances inside cell 1.
  - Source is truth; visual cell rendering is decoupled from source-text CT layout.

Spike is at `spikes/d12_cell_caret/`. Run via `./run.sh` (builds, wraps as `.app`, launches). Logs go to `/tmp/d12-spike.log` when launched via `run.sh`.

**Design is ratified** — D12 proceeds with `CellSelectionDataSource` as the primary approach. Overlay fallback unchanged; modal remains parked per memory `md_editor_d12_break_glass_fallback.md`.

---

## Test tiers remaining

Prioritized list CD and CC agreed to in the current session. Work down this list inside the spike, capturing findings against each tier in this file's "Findings by tier" section below.

### Tier 1 — click routing in all regions ✅ DONE

- [x] Click **cell 2** — PASS
- [x] Click the **padding zone between cells** — PASS (snaps to cell 2 start)
- [x] Click **outside both cells** — FIXED mid-session by removing TLM fallback; all out-of-cell clicks now route by x-midpoint.

### Tier 2 — keyboard navigation ✅ DONE (Tab untested but implemented)

- [x] **Left / Right arrow** at cell boundaries — PASS after `keyDown` override adds cell-skip.
- [x] **Backspace** at cell start / **Delete** at cell end — PASS after `deleteBackward`/`deleteForward` overrides add boundary protection.
- [~] **Tab / Shift+Tab** — implemented in the `keyDown` override; not yet exercised by CD.

### Tier 3 — multi-row tables ✅ DONE

Refactored the spike: `Row` struct + `parseRows` + `rowContaining` helpers; `CellDataSource` uses per-row cells keyed by `rowContaining(offset:)` with a **critical fix** — `lineFragmentRangeForPoint`'s `location` argument is the container anchor (offset 0), NOT the click's document position. Correct routing uses `tlm.textLayoutFragment(for: point)` to find the fragment actually hit by the click, then reads `rangeInElement.location` to identify the row.

All 11 cross-row tests PASS via the harness:
- Click row 2 cell 1 → caret in row 2 cell 1 ✓
- Click row 2 cell 2 → caret in row 2 cell 2 ✓
- Right arrow at row 1 c2 end → row 2 c1 start (skip pipes) ✓
- Left arrow at row 2 c1 start → row 1 c2 end ✓
- Tab at row 1 c2 → row 2 c1 start ✓
- Shift+Tab at row 2 c1 → row 1 c2 end ✓
- Delete-forward at row 1 c2 end → row 2 c1 start (non-destructive) ✓
- Backspace at row 2 c1 start → row 1 c2 end (non-destructive) ✓
- Typing in row 2 inserts at correct source offset, source updates correctly ✓
- Down arrow from row 1 offset 5 → row 2 offset 29 (same caret x preserved) ✓
- Each row gets its own `CellGridFragment` via the delegate ✓

**Implication for production:** the architecture scales to multi-row. `textLayoutFragment(for: point)` is the canonical way to resolve clicks to the right row in a multi-row table. Up/Down arrow navigation preserves caret column across rows via NSTextView's natural behavior — our enumerate yields the same x for same in-cell position, so vertical navigation finds the correct target.

---

## Automation harness (meta-infrastructure)

Added mid-session so CC can drive the spike without needing CD to click:

- **Command file poller** in `CommandFilePoller` polls `/tmp/d12-command.json` every 200ms. Supported actions:
  - `dump_state` → writes `/tmp/d12-state.json` (source, selection, parsed rows, tuning knobs, fragment rects)
  - `snapshot` → writes a PNG of the window content (CC reads via `Read` tool)
  - `window_info` → writes screen coords of window + content view
  - `cell_screen_rects` → writes each cell's SCREEN rect (top-left origin), enabling `cliclick` to target cells precisely without coord math
  - `reset_text` / `set_text` / `set_selection` → drive editor state

- **`cliclick`** (installed via Homebrew) for synthetic mouse clicks. `osascript -e 'tell application "System Events" to key code N'` for key events (arrow, Tab, Delete, Backspace, etc.).

- **Test loop from CC side:** write command JSON, read result JSON, optionally read snapshot PNG. Issue cliclick/osascript events. Repeat.

- **Works unattended** after macOS Accessibility permission is granted to osascript / cliclick one time. No per-test human loop required.

### Tier 4 — editing edge cases ✅ DONE

- [x] **Typing past cell width** — source updates correctly, but text **visually overflows** the cell box; cell 2's content draws on top of the overflow (no clipping). **Production:** `CellGridFragment.draw` must clip cell content to cell bounds (or wrap content within the cell width).
- [x] **Typing a literal `|`** in cell content — adds a NEW cell to the row's structure (`| cell| one | cell two |` parses as 3 cells). The spike's hardcoded-2-cell fragment doesn't adapt; production's `TableLayout` supports N cells, so it would render correctly. **Production policy needed:** auto-escape typed pipes to `\|`, allow the structural change, or block pipe input in cell-edit mode. Word/Docs would block.
- [x] **Empty cell** — `parseCellRanges` had to be rewritten to record zero-length ranges instead of skipping empty cells (the old "skip leading pipe + whitespace" loop swallowed empty cells entirely). After the fix, empty cells parse correctly. BUT: clicking into an empty cell + typing inserts the typed char into the NEXT cell, not the empty cell — because the +1 hack on `lineFragmentRangeForPoint` extends the range past the empty cell's content-end into the inter-cell whitespace, and NSTextView picks that offset for the click. **Production:** empty cells need either special-case caret routing constraining to the empty position, OR insert-time logic that detects "caret at offset just past empty-cell content" and redirects insert into the empty cell.

### Tier 5 — selection highlights ✅ DONE

- [x] **Drag-select within a cell** — implemented via `CellGridFragment.draw` querying `textLayoutManager.textSelections` and intersecting with each cell's source range. Critical fix: cell ranges from `parseCellRanges` are ROW-LOCAL; `textSelections` are ABSOLUTE. Must shift cell ranges by the row's absolute start offset (computed from `rangeInElement.location`) before intersecting.
- [x] **Drag-select across cells** — same mechanism; multi-cell selections highlight per-cell intersections, with the inter-cell pipe gap NOT highlighted. Cross-row selections highlight per-row per-cell.
- [~] **Cosmetic gap:** for cross-row selections, NSTextView still draws a default selection highlight band BETWEEN rows (over the source's pipe + newline + pipe characters). Production must suppress the default highlight rendering for table content (likely via overriding the layout manager's highlight drawing or returning an empty highlight rect for those source ranges).

### Tier 6 — secondary trigger (double-click → source mode) ✅ DONE

- [x] **Double-click a cell** drops THAT row to whole-row pipe-source mode (D8.1-style reveal). Per-row independent — double-clicking row 2 reveals row 2 only; row 1 remains as a grid.
- [x] **Escape** un-reveals all rows (returns them to grid mode). Production may want a more nuanced un-reveal (e.g., on caret leaving the revealed row).
- Implementation: `GridDelegate.revealedRowStartOffsets: Set<Int>` tracks which rows are revealed; the delegate returns a default `NSTextLayoutFragment` for those rows instead of `CellGridFragment`. `LoggingTextView.mouseDown` intercepts `clickCount==2` events and toggles the row's reveal state. **Production:** the same machinery already exists in D8.1 production code (`TableLayoutManagerDelegate.revealedTables`) — D12 just changes the trigger from "caret-in-range" to "double-click", per the D12 spec §3.6.

---

## Findings by tier

Append as you work through. Each finding: tier/case ID, expected, observed, implication for production.

### Tier 1 — click routing

- **1a** — click inside cell 2: PASS. Caret lands inside cell 2 at the clicked x; typing lands in cell 2.
- **1b** — click between cells (in the white gap): PASS. Snaps to the first position in cell 2. Alternate-acceptable: snapping to end of cell 1. Current implementation (post-fix): `lineFragmentRangeForPoint` always routes by x-midpoint between cells, so click in gap closer to cell 2 left edge → cell 2 (correct).
- **1c** — click outside both cells (any click past the cell rects): initially snapped to first position in cell 1 regardless of x. **FIXED** by removing the fallback path in `lineFragmentRangeForPoint` and always routing by x-midpoint: click x < midpoint → cell 1; x ≥ midpoint → cell 2. Far-right click now snaps to cell 2 end (via the caret-offset enumeration), far-left click snaps to cell 1 start.

**Implication for production:** `lineFragmentRangeForPoint` must be the sole click-routing path for table rows — never fall back to the TLM default for clicks in the row's y-band, because the default picks offsets via natural CT layout of the source text (pipes + whitespace), which is not what the user sees. Always return a cell-scoped `NSTextRange` computed from grid geometry.

### Tier 2 — keyboard navigation

- **2.4 Right arrow** within a cell and across boundaries: WORKS (per CD: "right arrow progresses one character at a time to end of text, then skips to end of first cell, then skips to next cell"). Right arrow advances source offset one per press. Between cells, offsets map to the cell's right-edge x (offsets 10, 11, 12 between cell 1 and cell 2 all yield x=332 — so two presses appear to "stuck" visually at the cell 1 right edge before the caret jumps into cell 2). CD accepts current behavior as "good" for the spike.

  **Implication for production:** consider overriding `NSTextSelectionNavigation.destinationSelectionForTextSelection(...)` so horizontal arrow at cell-content-end jumps directly to the next cell's start, skipping the pipe-character source offsets. Not required for correctness, but cleaner UX (one key press, one visual move).

- **Caret x accuracy** ("roughly correct, not perfect"): initial `perCharStride = 12pt` was an approximation. Changed to dynamic: `perCharStride = measure "M" in 18pt monospaced font`. Should tighten caret-to-character alignment in subsequent tests. (Will note in a follow-up finding after re-observation.)

- **2.5 Backspace at cell-2 start**: raw `deleteBackward` chews pipes. Observed sequence:
  - Source: `| cell one | cell two |\n` (24 chars, 2 cells)
  - Caret at offset 13 (start of "cell two"), backspace:
    - Press 1: deletes space at offset 12 → `| cell one |cell two |\n` (23 chars, still 2 cells)
    - Press 2: deletes pipe at offset 11 → `| cell one cell two |\n` (22 chars, **1 cell**). Cell 1 renders "cell one cell two"; cell 2 fragment still draws but empty.

  **Fix in spike (Word/Docs-like behavior):** `LoggingTextView.deleteBackward` override. If caret is at cell-2 start, jump to cell-1 end without deleting. If caret is at cell-1 start, jump to line start. Symmetric `deleteForward` override: caret at cell-1 end → jump to cell-2 start; caret at cell-2 end → jump to line end.

  **Implication for production:** the `NSTextView.deleteBackward` / `deleteForward` override surface is sufficient for cell-boundary protection. Alternative: override `NSTextSelectionNavigation.deletionRangesForTextSelection(...)` for a more principled answer. Production choice: probably the NSTextView overrides (simpler, localized to table-editing contexts).

  **Verified by CD 2026-04-24:** backspace at cell-2 start jumps to cell-1 end non-destructively; additional backspaces from there delete normally within cell 1. Symmetric delete-forward at cell-1 end works. "All the way around in both directions."

- **2.4 Arrow nav across cell boundaries** (re-tested after override): **PASS** all four corners.
  - Right arrow at cell-1 content-end → jumps directly to cell-2 content-start (one press, no pause).
  - Left arrow at cell-2 content-start → jumps directly to cell-1 content-end.
  - Right arrow at cell-2 content-end → ignored (hard right boundary).
  - Left arrow at cell-1 content-start → ignored (hard left boundary).

  **Implication for production:** a `keyDown` override on the editor NSTextView subclass, gated on `selection.length == 0` and a detected table-row context, is sufficient for cell-boundary arrow navigation. Alternative: `NSTextSelectionNavigation.destinationSelectionForTextSelection(...)` override, which is more principled but needs a full subclass.

- **2.6 Tab / Shift+Tab**: implemented in the same `keyDown` override but **untested by CD** in this session. Behavior: Tab in cell 1 → cell 2 start; Tab in cell 2 → cell 2 end. Shift+Tab in cell 2 → cell 1 end; Shift+Tab in cell 1 → cell 1 start. Should exercise in a later test pass.

### Caret visual alignment (tuning pass)

- **Problem 1 — caret Y above cell**: observed 2026-04-24. Cause: `fragmentHeight=40` with cells drawn at y=0; the line fragment's natural y-position was at y=0-17, but the cells drawn at y=0-40 appeared below where NSTextView actually drew the caret (specifically after the textContainerInset was factored in). Fixed by adding a `cellYOffset` tuning knob exposed as a live NSTextField in the window toolbar. CD dialed `cellYOffset = -7.5` (Menlo 18pt) for visual alignment.

- **Problem 2 — caret x not matching character**: `perCharStride` was hand-tuned to 12pt, slightly off from Menlo 18pt's natural ~11.13pt. Fixed by measuring char width dynamically from the font. CD then dialed `caretXOffset = 13` to fine-tune the caret's first-char position within each cell (the text content remains at a fixed 8pt inset — caret X is decoupled from text position).

- **Problem 3 — click past last char snaps to before last char**: classic off-by-one in NSRange→NSTextRange conversion. `NSRange(location: 2, length: 8)` maps to caret positions 2..9 inside the range, but the "after last char" position (offset 10) was being excluded. Fixed by adding `+1` to the length when constructing the `NSTextRange` returned from `lineFragmentRangeForPoint`, so the caret can land at content-end positions.

- **Problem 4 — rendering clipped on negative cellYOffset**: `renderingSurfaceBounds` returned a rect with non-negative origin, so cells drawn above the fragment's y=0 were clipped. Fixed by extending the bounds `±80pt` vertically (the header explicitly allows negative origins).

- **Problem 5 — tuning knobs didn't live-update**: `invalidateLayout(for:)` alone doesn't drop the CellGridFragment's cached render. Same issue D8.1 hit — fix is `storage.beginEditing` / `storage.edited(.editedAttributes, range:, changeInLength: 0)` / `endEditing` to force the fragment cache to evict, then invalidate + layout.

- **Final tuned values baked in**: `cellYOffset = -7.5`, `caretXOffset = 13`, `cellContentXInset = 8`, `perCharStride = measured "M" at Menlo 18pt`. These are the spike's defaults; production will need equivalent knobs (likely derived from font metrics instead of hard-coded numbers).

- **Implications for production**: tuning knobs should NOT be hard-coded numbers like 13 and -7.5. They should be derived from:
  - Font metrics (ascender, descender, leading) for Y alignment.
  - Font bearings and advance widths for caret X alignment.
  - Proper line-fragment + caret-rect geometry queries via NSTextLayoutManager.
  - The spike values are reference anchors; production must replace with derived formulas so alignment stays correct across font sizes, weights, and styles.

### UX improvements added mid-session (not a test tier, but worth noting)

- **In-window log pane** with **Copy logs** and **Clear** buttons — real-time event/state visibility without having to look at a terminal. Black-on-white so readable regardless of system dark/light mode (app is forced to Aqua appearance).
- **Split view**: top = editor inside a scroll view (production-like setup; no more cells-at-bottom-of-window artifact), middle toolbar = log + tuning controls, bottom = log pane.
- **Tuning knobs**: `cell Y:` and `caret X:` NSTextField inputs in the toolbar. Live-update on every character typed (via `controlTextDidChange`). `Reset` button restores to baked-in defaults.
- **`run.sh`**: bundles the SwiftPM executable into `D12Spike.app` with a proper `Info.plist` so macOS's window management works reliably. Without the app bundle, windows would sometimes be invisible or off-screen.

### Cell geometry — coord system reference

Confirmed in discussion 2026-04-24: the tuning offsets are **cell-relative**, not fragment-absolute. Three anchor constants drive all cell geometry:

```swift
let cell1X: CGFloat = 20
let cell2X: CGFloat = 360
let cellWidth: CGFloat = 320
```

All downstream geometry — cell draw rects, cell content text x, caret x per offset, click hit-test midpoint — is derived from these three. Changing `cell2X` (say, to reduce the inter-cell gap) propagates through everything without breaking the tuning knobs, because the offsets are per-cell.

**Implication for production**: the same separation should hold. `TableLayout`'s column positions are the "model anchors"; any per-cell tuning (paddings, offsets) should be expressed relative to those anchors, not to document-absolute coordinates. That mirrors the pattern CD uses in gantt/flowchart/UML editors — model shapes have positions; content within shapes has offsets. Moving shapes doesn't invalidate offsets.

---

## Known polish items (not blocking tier work)

- **Rows render at the bottom of the window**, not the top. Artifact of TextKit 2 NSTextView without a scroll view. Production uses a scroll view; not reproducing in production.
- **Caret slightly taller than cell content** in spike. Line fragment's natural font height slightly exceeds our cell height. Resolvable by matching `fragmentHeight` to font metrics precisely, or by letting the cell border grow to line height.
- **Trailing `\n` in source** — the current `initialSourceText` ends with `\n`. `parseCellRanges` correctly bails on newline now (after the infinite-loop fix), but the trailing offset produces an extra "| cell ..." default line fragment that NSTextView renders as a caret-parking spot. Expected in a real document (tables are followed by other content); probably fine.

---

## How to resume this session

### Quick start

1. **Build + launch the spike:**
   ```bash
   cd ~/src/apps/md-editor-mac/spikes/d12_cell_caret
   ./run.sh
   ```
   Window opens at screen (100, 100). App logs → `/tmp/d12-spike.log`.

2. **Tail the log** while testing (optional; the spike's in-window log pane is the primary view):
   ```bash
   tail -f /tmp/d12-spike.log
   ```

### CC-driven automation (new)

The spike is now fully remotable. CC writes JSON to `/tmp/d12-command.json`; the spike polls every 200ms and responds.

- **State dump:** `echo '{"action":"dump_state"}' > /tmp/d12-command.json` → reads `/tmp/d12-state.json`.
- **Snapshot:** `echo '{"action":"snapshot"}' > /tmp/d12-command.json` → reads `/tmp/d12-shot.png`.
- **Cell screen rects** (for cliclick targeting): `echo '{"action":"cell_screen_rects"}' > /tmp/d12-command.json` → reads `/tmp/d12-cells.json`.
- **Window info** (screen coords): `{"action":"window_info"}`.
- **State manipulation:** `{"action":"set_selection","location":N}`, `{"action":"reset_text"}`, `{"action":"set_text","text":"..."}`.

Synthetic input:
- Clicks: `cliclick c:<x>,<y>` (screen coords, top-left origin).
- Typing: `cliclick t:<chars>`.
- Arrow keys / modifier combos: `osascript -e 'tell application "System Events" to key code <N>'` (e.g., 123 left, 124 right, 125 down, 126 up, 48 tab, 51 backspace, 117 delete).

**macOS Accessibility permission:** granted once in System Settings → Privacy & Security → Accessibility for osascript + cliclick. Persists; no per-session re-grant.

### Resume prompt

Pass CC this path to pick up:

```
/Users/richardkoloski/src/apps/md-editor-mac/spikes/d12_cell_caret/STATUS.md
```

Or hand CC the following inline:

> Continue the D12 cell-caret spike. Read `spikes/d12_cell_caret/STATUS.md`. Tier 1, 2, 3 are complete; the automation harness is live. Pick up at Tier 4 (editing edge cases: typing past cell width, literal pipe, empty cells). Drive everything via the harness — don't ask CD for click tests. Record findings under "Findings by tier" as you work. Do not touch production `Sources/` yet — spike iteration only.

---

## State of git / repo (end of 2026-04-24)

All spike work is committed on `main`:

| Commit | Summary |
|---|---|
| `0be84bd` | D12 triad (spec + plan + prompt) drafted |
| `45d7dc3` | Phase 1 spike GREEN (caret-x validated via NSTextSelectionDataSource) |
| `917ec1c` | Spike v2: full round-trip (click → caret → edit in cell) |
| `2b878b7` | Caret visual alignment + tuning knob UX |
| `3223439` | Tier 3 multi-row GREEN + CC-driven automation harness |

Tier progress:

- Tier 1 — click routing ✅
- Tier 2 — keyboard navigation ✅
- Tier 3 — multi-row tables ✅ (11 behaviors via harness)
- **Visual parity** — cells now match production styling (labelColor borders, separator dividers, no fills) ✅
- Tier 4 — editing edge cases ✅ (3 findings, all production-relevant)
- Tier 5 — selection highlights ✅ (per-cell intersection drawing in CellGridFragment)
- Tier 6 — double-click → source mode ✅ (per-row independent reveal)

Harness + tuning infrastructure is production-grade for the spike's purposes. Tuning knobs (`cellYOffset=-7.5`, `caretXOffset=13`) baked in as spike defaults; production must replace with font-metric-derived formulas.

**All planned spike tiers complete.** Next phase: merge spike findings to production `Sources/`. Plan Phase 2 (10 steps) in `docs/current_work/planning/d12_per_cell_table_editing_plan.md`.
