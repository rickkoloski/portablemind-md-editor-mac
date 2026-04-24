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

### Tier 1 — click routing in all regions

- [ ] Click **cell 2** — verify it routes to cell 2, not cell 1.
- [ ] Click the **padding zone between cells** — should snap caret to the nearest cell edge.
- [ ] Click **outside both cells** (left margin, right margin, below cells) — snap to nearest cell edge.

### Tier 2 — keyboard navigation

- [ ] **Left / Right arrow** at cell boundaries — should cross cells; pipe chars not directly visitable.
- [ ] **Backspace** at cell start / **Delete** at cell end — cross cells cleanly, don't delete pipes.
- [ ] **Tab / Shift+Tab** — cell-to-cell navigation (needs explicit key binding).

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

*(empty — new tiers will land here as we work through them)*

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
