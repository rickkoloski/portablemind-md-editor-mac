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

### Tier 3 — multi-row tables

- [ ] Add a **second row** to the source (`| c1a | c2a |\n| c1b | c2b |`). Verify each row gets its own `CellGridFragment`, cells route independently, **Up / Down arrow** crosses rows.

### Tier 4 — editing edge cases

- [ ] Typing **past the cell's visible width** — cell content grows; decide whether to wrap or overflow.
- [ ] Typing a literal **pipe `|`** inside a cell — does it corrupt the grid parse?
- [ ] **Empty cell** (`| | cell two |`) — click into empty space, type.

### Tier 5 — selection

- [ ] **Drag-select within a cell** — highlight constrained to cell.
- [ ] **Drag-select across cells** — per-cell highlights, not flat source highlight.

### Tier 6 — secondary trigger (double-click source mode)

- [ ] **Double-click a cell** — drop to whole-table source reveal (D8.1 mechanism repurposed).

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

1. **Rebuild + launch:**
   ```bash
   cd ~/src/apps/md-editor-mac/spikes/d12_cell_caret
   ./run.sh
   ```
   The window opens at screen position (100, 100) — bottom-left of primary display. Logs at `/tmp/d12-spike.log`.

2. **To tail logs while interacting:**
   ```bash
   tail -f /tmp/d12-spike.log
   ```

3. **Resume prompt:** hand CC the following:
   ```
   Continue the D12 cell-caret spike. Read
   spikes/d12_cell_caret/STATUS.md — pick up at the next unchecked
   Tier item. Iterate on the spike only; do not touch production
   Sources/ yet. Record findings in STATUS.md under "Findings by tier"
   as you work.
   ```

   Or paste this path:
   ```
   /Users/richardkoloski/src/apps/md-editor-mac/spikes/d12_cell_caret/STATUS.md
   ```

---

## State of git / repo

- Spike code + FINDINGS.md committed in `0be84bd` (earlier today).
- Spike v2 refinements (custom fragment + refined parser + cells-flush-to-top) **uncommitted as of this status write**. Commit queued — see next section.
- `D12Spike.app/` bundle generated on disk by `run.sh` — gitignored via `.gitignore` entry added this session (`spikes/**/*.app/`).
- `/tmp/d12-spike.log` is ephemeral; not in repo.

---

## Commit queue (on resume, commit first)

Files to add + describe:
- `spikes/d12_cell_caret/Sources/D12Spike/main.swift` — spike v2: custom fragment + delegate + data source round trip.
- `spikes/d12_cell_caret/run.sh` — build + `.app`-wrap + launch helper.
- `spikes/d12_cell_caret/STATUS.md` — this file.
- `.gitignore` — `spikes/**/*.app/` entry.

Commit message draft:
```
D12 spike v2: full round-trip validated (click → caret → edit in cell)

Extends the Phase 1 spike from just caret-x validation to a full
round-trip reproducer: custom NSTextLayoutFragment draws two cells,
custom NSTextSelectionDataSource routes clicks and caret offsets to
cell bounds, typing inserts at source offsets and the cell re-renders
from storage. CD verified end-to-end: click cell 1 → caret inside
cell 1 → type 'x' → "cell one" becomes "cellx one" → caret advances
inside cell 1.

Spec and plan already reflect the NSTextSelectionDataSource design
(committed in 45d7dc3); this commit captures the iteration that
proved the full round trip, not just caret-x.

Adds run.sh (build + .app-wrap + launch) because raw swift-run
doesn't activate windows reliably on macOS 15. STATUS.md tracks
the remaining test tiers CD asked to cover in isolation before
merging to production.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```
