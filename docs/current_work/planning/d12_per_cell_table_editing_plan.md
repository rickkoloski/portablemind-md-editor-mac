# D12: Per-Cell Table Editing — Implementation Plan

**Spec:** `d12_per_cell_table_editing_spec.md`
**Created:** 2026-04-24

---

## Overview

Replace D8.1's "single-click → whole-table source reveal" with "single-click → caret in cell" as the primary editing path. Keep D8.1's source-mode machinery for the secondary double-click path. Load-bearing technical bet: TextKit 2's `NSTextLayoutFragment.textLineFragments` can be overridden to return per-cell line fragments whose bounds NSTextView honors for caret drawing. A bounded spike validates this before the production work.

---

## Prerequisites

- [ ] D8 grid rendering on `main` (commit `99dc2a9`).
- [ ] D8.1 reveal machinery on `main` (commit `f5e206e`) — repurposed, not removed.
- [ ] Build green before starting.
- [ ] Decision ratified with CD: spec §3.4 primary approach = TextKit-native line-fragment mapping; fallback = NSTextField overlay.

---

## Phase 1 — Spike (RESOLVED 2026-04-24)

### Result

**GREEN on revised hypothesis.** Original hypothesis (override `NSTextLayoutFragment.textLineFragments`) invalidated by header reading — `NSTextLineFragment.typographicBounds` readonly. Revised hypothesis (custom `NSTextSelectionDataSource`) validated by minimal SwiftPM spike at `spikes/d12_cell_caret/`. Caret visually drew at custom x-values honored by `enumerateCaretOffsetsInLineFragment`.

See `spikes/d12_cell_caret/FINDINGS.md` for full findings, including:
- Why the original hypothesis is dead (readonly typographic bounds).
- Empirical evidence the DataSource path works (click/type observations).
- Subtleties: enumeration must be left-to-right monotonic; `lineFragmentRangeForPoint` must return cell-scoped ranges (not row-scoped) for clicks to route by grid geometry instead of natural CT layout.

Phase 2 proceeds with the DataSource approach.

---

## Phase 2 — Production implementation (assuming spike is Green)

### Step 1: `cellRanges` on `TableLayout`

**Files:** `Sources/Editor/Renderer/Tables/TableLayout.swift`, `Sources/Editor/Renderer/MarkdownRenderer.swift`

Add:

```swift
/// Per-cell source NSRange in the markdown buffer.
/// `cellRanges[rowIndex][columnIndex]` = range of cell's content
/// (exclusive of surrounding pipes and whitespace).
let cellRanges: [[NSRange]]
```

Populate from `visitTable`:
- Reuse existing cell-extraction logic that produces `cellContentPerRow`.
- At each cell-extraction point, also capture the source NSRange of the trimmed cell content.
- Handle GFM `\|` escape: split on unescaped pipes only (simple state machine, single char lookbehind).
- Empty cells → zero-length range at the appropriate offset.
- Missing trailing pipe → last cell extends to end-of-line.

### Step 2: `CellSelectionDataSource` — custom `NSTextSelectionDataSource`

**Files:** new `Sources/Editor/Renderer/Tables/CellSelectionDataSource.swift`; wiring in `Sources/Editor/EditorContainer.swift`.

Create a class `CellSelectionDataSource: NSObject, NSTextSelectionDataSource` that wraps the existing `NSTextLayoutManager`. It holds a weak reference to the TLM and forwards most data-source protocol methods (`documentRange`, `enumerateSubstrings`, `locationFromLocation`, `offsetFromLocation`, `baseWritingDirection`, `textLayoutOrientation`, `enumerateContainerBoundaries`, `textRangeForSelectionGranularity`) to the TLM's own conformance.

Override only two methods:

**`enumerateCaretOffsetsInLineFragment(at:using:)`** — if `location` falls inside a table row (detected via `TableRowAttachment` on the text-storage attribute at that offset):
- Look up the row's `TableLayout` and `cellContentIndex`.
- For each cell in the row, in left-to-right order:
  - For each source-character offset within the cell's range, yield `(caretX, location, leadingEdge, stop)` with `caretX = columnLeadingX[col] + localOffset * perCharStride` (where `perCharStride` is derived from the cell's pre-rendered content width / character count).
  - Yield pipe-character offsets in a narrow x-range between cells (acts as a dead zone; these chars won't be landed-on by clicks but the data source still has to enumerate them for NSTextView's consistency).
- For non-table rows, delegate to the TLM's default enumeration.

**`lineFragmentRange(for:inContainerAt:)`** — hit-test `point` against the grid:
- If the point falls within a cell's visual rect (y inside row bounds, x inside `columnLeadingX...columnTrailingX`), return an `NSTextRange` covering only that cell's source range.
- Else, delegate to the TLM's default.

Install on the text view after construction:

```swift
if let tlm = textView.textLayoutManager {
    let ds = CellSelectionDataSource(wrapping: tlm)
    tlm.textSelectionNavigation = NSTextSelectionNavigation(dataSource: ds)
    coordinator.cellDataSource = ds  // retain
}
```

Invariants from spike findings (violations confuse NSTextView):
- Enumeration must be strictly left-to-right in x.
- `lineFragmentRange` must return cell-scoped ranges (not row-scoped) when hitting a cell; otherwise NSTextView resolves offsets via natural CT layout and ignores our caret x-values for click-routing.

### Step 3: Renderer drops paragraph-style for revealed tables

**Files:** `Sources/Editor/Renderer/MarkdownRenderer.swift`, `Sources/Editor/EditorContainer.swift`

Inject the reveal-state set into the renderer:
- `MarkdownRenderer` gains a `revealedTables: Set<ObjectIdentifier>` input (or closure-returning-set, to avoid re-rendering when the set changes).
- `visitTable` consults the set. If the just-built layout's ID is *in* the set (only possible on re-render of an already-revealed table), omit `.paragraphStyle` on all rows.

The Coordinator's `adjustParagraphStyles(revealed:...)` helper retires (see Step 7).

### Step 4: Single-click → cell caret placement

**Files:** `Sources/Editor/LiveRenderTextView.swift` (or override via subclass pattern already in place)

Override `mouseDown(with:)`:

```swift
override func mouseDown(with event: NSEvent) {
    let clickPoint = convert(event.locationInWindow, from: nil)
    // 1. Look up fragment at clickPoint via textLayoutManager
    // 2. If fragment is TableRowFragment:
    //    - If clickCount == 1: compute (row, col) from click.x vs layout.columnLeadingX,
    //      compute cell-local offset via CTLineGetStringIndexForPosition on the
    //      cell's attributed string, set selectedRange.
    //    - If clickCount == 2: toggle whole-table reveal (Step 5).
    //    - Don't call super.
    // 3. Else: super.mouseDown(with: event)
}
```

### Step 5: Double-click → whole-table source mode

**Files:** `Sources/Editor/LiveRenderTextView.swift`, `Sources/Editor/EditorContainer.swift`

- `mouseDown` with `clickCount == 2` in a cell calls into the Coordinator's `revealTable(_:)` method.
- `revealTable` is extracted from the old `updateTableReveal` — it adds the table's layout ID to `delegate.revealedTables` and invalidates.
- Un-reveal still happens on caret exit (existing path, minus the auto-reveal-on-enter half).

Handle Q4 refinement: double-click inside cell *content* should select the word (standard macOS behavior). Double-click on cell padding / borders drops to source mode. If the hit region for "padding vs content" is too small in practice, fall back to:
- Menu command `Edit → Edit Table as Source` (always works).
- `Cmd+Shift+E` keyboard shortcut bound to the same command (always works).

Gesture-based trigger is a nice-to-have; menu + keyboard are the required paths.

### Step 6: Cell-boundary keyboard navigation

**Files:** `Sources/Editor/Keyboard/` (likely a new file `CellBoundaryCommands.swift`)

Intercept relevant keys when the caret is inside a cell:

- `Tab` → advance to next cell's range start. Wrap to next row's first cell; at last cell of last row, move caret to the paragraph after the table (using `NSTextStorage.mutableString`'s paragraph navigation).
- `Shift+Tab` → reverse.
- `←` at cell-range start → previous cell's end (skip pipe source chars).
- `→` at cell-range end → next cell's start.
- `↑` / `↓` — defer to TextKit natural behavior; line fragments stacked correctly should produce the right result. Verify during testing; fall back to custom routing if not.

Implementation pattern: subclass `NSTextView.keyDown(with:)` OR register `NSTextInputClient` commands. Match existing D4 mutation-command wiring.

### Step 7: Retire old paragraph-style mutation machinery

**Files:** `Sources/Editor/EditorContainer.swift`

Remove (or gut):
- `Coordinator.adjustParagraphStyles(in:revealed:storage:)` — paragraph-style decision now owned by renderer (Step 3).
- Auto-reveal path in `updateTableReveal`. The function still exists for UN-reveal-on-exit, but loses the single-click-triggered entry into reveal. Rename to `updateTableUnreveal` or merge into `revealTable` / `unrevealTable` pair.

Keep:
- `findTableRange(for:in:)` — still needed for un-reveal after a re-render replaces the `TableLayout` instance.
- `revealedTableLayoutID` coordinator state — repurposed as "the ID of the currently-revealed table (via double-click or menu), if any."
- `.editedAttributes` + `invalidateLayout` transaction pattern — required for fragment re-cache drop on state change.

### Step 8: Selection rendering across cells

**Files:** `Sources/Editor/Renderer/Tables/TableRowFragment.swift`

Extend `draw(at:in:)`:
- If the current `textLayoutManager.textSelections` intersects this row's source range, compute per-cell selection rects by intersecting the selection's ranges with each cell's `cellRanges[row][col]`.
- Fill each cell's intersection region with `NSColor.selectedTextBackgroundColor` before drawing cell content.
- Skip pipe characters in the highlight — they're not "selected" visually, even though source selection spans them.

Copy / cut operations on multi-cell selections: extract the per-cell source substrings, rejoin with pipes, write to pasteboard. Handled in `LiveRenderTextView.copy(_:)` override or `NSServicesMenuRequestor`.

### Step 9: Paste normalization

**Files:** `Sources/Editor/LiveRenderTextView.swift`

Override `paste(_:)`:
- If caret is inside a cell range, transform pasted string: `\n` → ` `, pipes → `\|`.
- Insert via normal `NSTextStorage.replaceCharacters`.
- If caret is in source mode (D8.1 revealed path), unchanged — normal paste into source buffer.

### Step 10: Undo grouping

**Files:** touches `Sources/Editor/EditorContainer.swift` / `LiveRenderTextView.swift`

Verify: typing a sequence of characters in one cell groups into one undo operation (matches existing NSTextView behavior). If typing triggers renderCurrentText mid-session and that disrupts undo grouping, use `NSUndoManager.groupsByEvent = false` + explicit `beginUndoGrouping` / `endUndoGrouping` around the cell-edit session.

---

## Phase 3 — Integration + validation

### Step 11: Manual test plan

**File:** `docs/current_work/testing/d12_per_cell_table_editing_manual_test_plan.md`

Mirror the D8.1 test plan structure. Sections:
- **Setup** (same build + launch commands).
- **A — Cell-level editing core** (click, caret position + size, type, arrow-out).
- **B — Cell boundary navigation** (Tab, Shift+Tab, arrow keys).
- **C — Selection across cells** (drag-select, copy, paste normalization).
- **D — Whole-table source mode** (double-click + menu command + keyboard shortcut; caret position + size correct this time).
- **E — Multi-table independence** (unchanged from D8.1).
- **F — Edge cases** (empty cells, wrapped cells, pipe-escape, last row, first row).
- **G — Regression checks** (D8 grid, D9 scroll-to-line, D10 line numbers, D11 CLI, delimiter reveal).
- **H — Engineering standards** (grep for `.layoutManager`).

### Step 12: Retire D8.1 manual test plan

Move `docs/current_work/testing/d08_1_manual_test_plan.md` to `docs/chronicle_by_concept/tables/` (create the directory) when D12 ships. The plan is accurate for D8.1's behavior but D12 changes the trigger, making the plan misleading in-place.

### Step 13: COMPLETE doc + roadmap + commit + push

- `docs/current_work/stepwise_results/d12_per_cell_table_editing_COMPLETE.md` — files changed, findings (expect: at least one line-fragment-bounds gotcha, one keyboard-nav edge case), deviations from spec+plan, supersession of D8.1.
- Update `docs/roadmap_ref.md`: D12 row → ✅ Complete, change-log entry. Also retroactively mark D8.1 as **Superseded by D12** in the status column (but keep it in the table for continuity).
- Update D8.1 COMPLETE doc with a header note: "Superseded by D12 on <date>. Whole-table reveal machinery retained; trigger changed from single-click to double-click / menu command."
- Update Harmoniq #1386: mark status = completed with a link to D12 deliverable, OR rename to point at the D12 deliverable and close.
- Commit + push.

---

## Testing (beyond manual)

- No new XCUITest in D12 (UI automation comes later, as noted in the D8.1 manual test plan's graduation section).
- Spike (Phase 1) produces no committed code — result is a plan revision and the go/no-go decision.
- Phase 2 steps 1–3 are unit-testable via the existing `MarkdownRendererTests` approach — add tests for `cellRanges` correctness (pipe-escape, empty cells, trailing-pipe-optional).
- Phase 2 steps 4+ are integration territory; covered by the manual test plan in Step 11.

---

## Verification checklist

- [ ] Spike Phase 1 produced a Green (or Yellow with accepted constraints) decision.
- [ ] `grep -r '\.layoutManager' Sources/` shows no new production references.
- [ ] Single-click in any grid cell lands caret inside the cell at natural line height.
- [ ] Typing updates the cell content; grid stays rendered; caret tracks.
- [ ] Tab / Shift+Tab cycles cells.
- [ ] Double-click drops to source mode; caret correctly positioned and sized.
- [ ] `Edit → Edit Table as Source` menu works.
- [ ] Drag-select across cells renders per-cell highlights.
- [ ] Cmd+Z undoes a cell edit as one operation.
- [ ] D8 / D9 / D10 / D11 / delimiter reveal all still work.
- [ ] D8.1 marked superseded; its test plan archived.
- [ ] Harmoniq #1386 closed or updated.

---

## Risks

1. ~~**Spike Red outcome**~~ — **Resolved GREEN** on revised hypothesis. Primary path is `CellSelectionDataSource`, not line-fragment override.
2. **Double-click collision with word-select** — macOS users will expect double-click-in-text to select a word. Mitigation: menu command + keyboard shortcut are always available; gesture is the optional surface.
3. **Keyboard nav across row boundaries with differing column widths** — up/down arrow snapping behavior may feel off. Mitigation: document in test plan, accept minor visual jumpiness for V1.
4. **Selection rendering performance** — painting per-cell highlight rects on every redraw during drag may stutter on large tables. Mitigation: cache the intersection result; only recompute when selection changes.
5. **Undo grouping disruption** — if renderCurrentText's mid-typing attribute rewrite breaks NSUndoManager's typing-session coalescing, user sees single-character undo steps. Mitigation: explicit undo grouping in LiveRenderTextView.
6. **DataSource enumeration cost** — `enumerateCaretOffsetsInLineFragment` runs on every selection change and yields one entry per source character. Large tables (100+ rows × dense cells) may produce perceptible lag if enumeration does too much work. Mitigation: cache per-row caret-offset tables on `TableLayout`, compute once at render, read at enumerate. Spike's log showed enumeration of 24 offsets in <1ms — well-bounded for reasonable table sizes.
7. **macOS version drift** — the DataSource override approach relies on NSTextView's current (macOS 14+) behavior of consulting the data source for caret drawing. Future macOS releases may change this. Mitigation: spike is re-runnable (`spikes/d12_cell_caret/`) for re-validation on each macOS bump; behavior is exercised by the manual test plan.
