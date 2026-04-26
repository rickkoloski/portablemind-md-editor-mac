## D13: Cell-Edit Overlay — Production Plan

**Spec:** `d13_cell_edit_overlay_spec.md` (260 lines, includes §3.12 modal popout)
**Spike:** `spikes/d13_overlay/` — GREEN across all 7 tiers (commits `7ecb072`, `96b84be`, `23475a0`, `8dfe198`, `27bb838`)
**Spike findings:** `spikes/d13_overlay/FINDINGS.md` — math algorithm + 12 production-merge constraints + go/no-go GREEN
**Created:** 2026-04-26

---

## Overview

Replace D12's single-click `snapCaretToCellContent` path with the cell-edit overlay validated in `spikes/d13_overlay/`. Add the modal popout (spec §3.12) as a parallel right-click path. Preserve all D12 / D8.1 mechanisms (cellRanges, CellSelectionDataSource, double-click reveal, cell-boundary keyboard nav between cells).

**Spike-to-production translation:** the spike code is throwaway, but the design decisions, math, and architectural patterns it validated are inputs to this plan.

---

## Prerequisites

- [ ] D12 shipped at v0.1 (commit `30f65a9`, tag `v0.1`).
- [ ] D13 spike GREEN (commits per §header).
- [ ] D13 spec §3.7 (active-cell border affordance) and §3.12–3.13 (modal popout + handoff) reviewed.
- [ ] Build green on `main`.

---

## Per-phase test gate (enforced)

Each phase's commit must pass automated harness validation before moving on. The harness extends the production `Sources/Debug/HarnessCommandPoller.swift` (D12 introduced this with `// TEST-HARNESS:` discoverability). Per-phase test cases below include the specific harness actions to drive and the assertions to verify before commit. CD direction 2026-04-26: "automated testing at each phase would be a solid step to enforce."

**Harness extensions for D13** (added in Phase 2, used through Phase 6):
- `dump_state.overlay` block: `{ active, row, col, cellRangeLocation, cellRangeLength }`.
- `show_overlay_at_table_cell` (table, row, col, [caret]) — programmatic overlay mount.
- `query_caret_for_click` (table, row, col, relX, relY) → returns `localCaretIndex`.
- `commit_overlay`, `cancel_overlay`, `advance_overlay_tab` (backward).
- `type_in_overlay` (text).
- `open_modal_at_table_cell` (table, row, col), `commit_modal`, `cancel_modal`.
- `set_overlay_text` (text) — replace overlay content (used for empty / large content tests).

Production harness keeps its `// TEST-HARNESS:` comment markers per project convention so it remains greppable for future cleanup.

---

## Phase 1 — `TableLayout.cellLocalCaretIndex`

**Files:** `Sources/Editor/Renderer/Tables/TableLayout.swift`

Add a new method to `TableLayout` (extension), porting the spike's algorithm verbatim:

```swift
extension TableLayout {
    /// Click-to-caret math per D13 spec §3.5.
    ///
    /// Convert (relX, relY) in cell-content-local coords to a local
    /// character index in cellContentPerRow[rowIdx][colIdx]. Caller
    /// computes relX/relY by subtracting (fragmentOrigin + columnLeadingX,
    /// fragmentOrigin + cellInset.top) from a click point in container coords.
    ///
    /// Algorithm:
    ///   1. CTFramesetterCreateWithAttributedString on the cell.
    ///   2. Suggest a frame at (contentWidths[colIdx], ∞).
    ///   3. CTFrameGetLines.
    ///   4. Stack lines, accumulating ascent + descent + leading.
    ///   5. Find the line containing relY → CTLineGetStringIndexForPosition(line, (relX, 0)).
    ///   6. Below all lines → return content.length. Above first → 0.
    ///   7. Clamp to [0, content.length]; kCFNotFound → 0.
    func cellLocalCaretIndex(rowIdx: Int, colIdx: Int,
                             relX: CGFloat, relY: CGFloat) -> Int { ... }
}
```

**Phase 1 test gate (automated):**
- Add `query_caret_for_click` action to production harness.
- Add unit test in `MdEditorTests/TableLayoutTests.swift` (or create the file if absent): synthesize a TableLayout with known cell content, call `cellLocalCaretIndex` at known coords, assert. Cases:
  - single-line cell start (relX=0, relY=0) → 0
  - single-line cell mid-range → expected char index
  - single-line cell past-end (large relX) → content.length
  - wrapped 3-line cell, line 2 click (relY ≈ 22 with default font) → index falls within line 2's source range
  - wrapped cell line 3 → index in line 3's range
  - above first line (relY=-5) → 0
  - below all lines (relY=10000) → content.length
- Harness-driven smoke test against a running app: load a doc with the spike's seed buffer, call `query_caret_for_click` for each case, assert the returned index matches expectation.
- **Phase 1 not commitable until both unit + harness tests green.**

---

## Phase 2 — `CellEditOverlay` + `CellEditController`

**Files (new):**
- `Sources/Editor/Renderer/Tables/CellEditOverlay.swift`
- `Sources/Editor/Renderer/Tables/CellEditController.swift`

### `CellEditOverlay`

NSTextView subclass. Spec §3.7 + §3.10:

- `commitDelegate: CellEditOverlayDelegate` — protocol with `overlayCommit`, `overlayCancel`, `overlayAdvanceTab`.
- `commonInit()` configures: `isRichText = false`, `allowsUndo = true`, `drawsBackground = true`, `backgroundColor = .textBackgroundColor`, `textContainerInset` set per-show (= `cellInset`), `textContainer.lineFragmentPadding = 0`, `textContainer.widthTracksTextView = true`.
- Active-cell affordance: `wantsLayer = true`, `layer.borderWidth = 2.0` (production may tune from spike's 2.5), `layer.borderColor = NSColor.controlAccentColor.cgColor`.
- `keyDown(with:)` intercepts: keyCode 53 (Escape) → cancel, keyCode 48 (Tab) → advanceTab(backward: shift), keyCode 36/76 (Return/Enter) → commit. Others → super.

### `CellEditController`

Coordinator-owned (held by `EditorContainer.Coordinator`). Spec §3.1, §3.2, §3.3:

- Holds singleton overlay (created on first show; reusable; spike used throwaway pattern, production may keep a single instance and re-configure).
- `showOverlay(attachment:rowIdx:colIdx:tableRowSourceRange:localCaretIndex:fragmentFrame:)` — computes cell rect (full cell incl. cellInset gutter), creates/reconfigures overlay, sets text container size, mounts as subview of host text view, calls `makeFirstResponder`. Captures `tableFirstRowLoc` for Tab anchoring (spike pattern).
- `commit()` — applies pipe-escape (`\\` → `\\\\` first, then `|` → `\|`) and newline normalization (`\n` → space). Splices via `replaceCharacters(in: cellRange, with: ...)`. Triggers `renderCurrentText` (production's existing re-render entry point). Computes char delta → updates `lastCommitAnchor.tableFirstRowLoc`. Tears down overlay.
- `cancel()` — discards overlay edits, tears down.
- `teardown()` — removes subview, clears state, `makeFirstResponder(host)`.
- `overlayAdvanceTab(_:backward:)` — Phase 4 expands; Phase 2 stub: `commit()`.

### Wiring in `EditorContainer.Coordinator`

After existing `CellSelectionDataSource` install:
```swift
let controller = CellEditController(hostView: textView)
coordinator.cellEditController = controller   // retain
```

**Phase 2 test gate (automated):**
- Add harness actions: `show_overlay_at_table_cell`, `commit_overlay`, `cancel_overlay`, `type_in_overlay`, `set_overlay_text`. `dump_state` payload extended with `overlay` block.
- Harness sequence: show overlay on a body cell → assert `dump_state.overlay.active == true` and matches expected row/col/cellRange. Type a char → assert overlay's content reflects insert. Commit → assert source updated, overlay dismissed. Show then cancel → assert source unchanged.
- Snapshot test: capture screenshot after `show_overlay_at_table_cell` on a wrapped cell at caret 43 (mirrors spike Tier 3 visual). Compare to a known-good baseline (a PNG checked into `MdEditorTests/Fixtures/d13_overlay_wrapped_cell_caret_43.png`) — exact-match assertion via `Data(contentsOf:)` byte equality, OR pixel-diff threshold if anti-aliasing varies.
- **Phase 2 not commitable until lifecycle round-trip + visual baseline green.**

---

## Phase 3 — `LiveRenderTextView.mouseDown` integration

**Files:** `Sources/Editor/LiveRenderTextView.swift`

Spec §3.2, §3.9, §3.10. The current D12 `mouseDown` does `snapCaretToCellContent` after super; replace with overlay show.

```swift
override func mouseDown(with event: NSEvent) {
    // Double-click → existing reveal path (D12 retained mechanism).
    if event.clickCount == 2 {
        // Existing onDoubleClickRevealRequest → Coordinator.revealRow(...) path.
        // Unchanged from D12.
        super.mouseDown(with: event)
        return
    }

    // Single-click → cell hit-test; show overlay if a TableRowFragment cell.
    guard let tlm = textLayoutManager,
          event.clickCount == 1 else {
        super.mouseDown(with: event)
        return
    }
    let viewPoint = convert(event.locationInWindow, from: nil)
    let inset = textContainerInset
    let containerPoint = CGPoint(x: viewPoint.x - inset.width,
                                 y: viewPoint.y - inset.height)
    guard let frag = tlm.textLayoutFragment(for: containerPoint),
          let row = frag as? TableRowFragment,
          let attachment = (row).attachment,  // production uses internal access
          attachment.kind != .separator,
          let cci = attachment.cellContentIndex else {
        super.mouseDown(with: event)
        return
    }

    // Skip if row is in source-reveal mode (D8.1 path).
    if let coord = (delegate as? EditorContainer.Coordinator),
       coord.isRowRevealed(attachment.layout.tableRange) {
        super.mouseDown(with: event)
        return
    }

    // Locate column.
    let layout = attachment.layout
    let xInFrag = containerPoint.x - frag.layoutFragmentFrame.origin.x
    var colIdx = -1
    for c in 0..<layout.contentWidths.count {
        let leftEdge = layout.columnLeadingX[c] - layout.cellInset.left
        let rightEdge = layout.columnTrailingX[c] + layout.cellInset.right
        if xInFrag >= leftEdge && xInFrag < rightEdge {
            colIdx = c
            break
        }
    }
    guard colIdx >= 0 else { super.mouseDown(with: event); return }

    // Click-to-caret math (Phase 1).
    let cellContentOriginX = frag.layoutFragmentFrame.origin.x + layout.columnLeadingX[colIdx]
    let cellContentOriginY = frag.layoutFragmentFrame.origin.y + layout.cellInset.top
    let relX = containerPoint.x - cellContentOriginX
    let relY = containerPoint.y - cellContentOriginY
    let localCaretIndex = layout.cellLocalCaretIndex(
        rowIdx: cci, colIdx: colIdx, relX: relX, relY: relY)

    // Compute the row's source range from the fragment's element range.
    guard let element = frag.textElement,
          let textRange = element.elementRange else {
        super.mouseDown(with: event); return
    }
    let docStart = tlm.documentRange.location
    let rowLoc = tlm.offset(from: docStart, to: textRange.location)
    let rowLen = tlm.offset(from: textRange.location, to: textRange.endLocation)
    let rowSourceRange = NSRange(location: rowLoc, length: rowLen)

    coordinator?.cellEditController?.showOverlay(
        attachment: attachment,
        rowIdx: cci, colIdx: colIdx,
        tableRowSourceRange: rowSourceRange,
        localCaretIndex: localCaretIndex,
        fragmentFrame: frag.layoutFragmentFrame)
}
```

**Cleanups:**
- Remove `snapCaretToCellContent()` and its call site (Q7).
- `CellSelectionDataSource` stays — it still routes click hit-tests for non-overlay scenarios (e.g., when in revealed-row source mode, drag-select within a cell is still data-source-driven).

**Phase 3 test gate (automated):**
- Use cliclick + harness `cell_screen_rects` action (port from spike) to perform a real synthetic click on a cell's screen coords; verify via `dump_state` that the overlay is active on the right cell.
- Perform synthetic click on the wrapped cell's visual line 2 (compute screen coords from cell rect + line metrics); verify overlay opens with caret on line 2 (this is the PRIMARY end-to-end validation).
- Click on a separator row → no overlay opens (verify `dump_state.overlay.active == false`).
- Click outside any table → no overlay (verify same).
- Double-click on a cell → reveal mode triggers (existing D12 path, regression check).
- **Phase 3 not commitable until synthetic-click → overlay → caret-position chain green for all cases.**

---

## Phase 4 — Tab navigation + scroll observer

**Files:** `Sources/Editor/Renderer/Tables/CellEditController.swift`, `Sources/Editor/EditorContainer.swift`

### Tab nav (spec §3.10, spike Tier 5)

Implement `overlayAdvanceTab(_:backward:)`:

1. Capture (curRow, curCol, layout) BEFORE commit.
2. Compute next (row, col): `nextCol = curCol + (backward ? -1 : 1)`. If wraps past end of row, `nextCol = 0; nextRow += 1`. If past start, `nextCol = colCount - 1; nextRow -= 1`.
3. **Production: skip header row in cycle.** If `nextRow == 0` (header), treat as out-of-bounds.
4. If `nextRow` out of `[1, cellContentPerRow.count - 1]` → commit + dismiss.
5. Save `TableAnchor { tableFirstRowLoc }` BEFORE commit (spike pattern).
6. `commit()` (re-renders, destroys old layouts).
7. Re-walk attributes; group by layout instance ID; pick the table whose first-row offset is closest to anchor (delta-aware).
8. Locate `nonSepRows[nextRow]`; get its fragment via `tlm.textLayoutFragment(for: rowStart)`.
9. `showOverlay(... localCaretIndex: 0)` — caret at start of new cell (Numbers convention).

### Scroll observer (spec §3.6 V1)

In `CellEditController.showOverlay`, after mounting:
```swift
if let scrollView = host.enclosingScrollView {
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(scrollViewWillStartLiveScroll(_:)),
        name: NSScrollView.willStartLiveScrollNotification,
        object: scrollView)
}
```

`@objc func scrollViewWillStartLiveScroll(_:)` → `commit()`.

In `teardown()`:
```swift
NotificationCenter.default.removeObserver(self,
    name: NSScrollView.willStartLiveScrollNotification,
    object: nil)
```

**Phase 4 test gate (automated):**
- Add harness `advance_overlay_tab` action.
- Harness sequence on multi-row table: show overlay on row 1 col 0 → advance Tab → assert row 1 col 1. Tab again → assert row 2 col 0 (cross-row). Shift+Tab → assert back to row 1 col 1. Tab past last cell of last body row → assert overlay dismissed.
- **Header exclusion test:** show overlay on row 1 col 0 (first body cell) → Shift+Tab → assert overlay DISMISSED (not row 0 col N — header excluded per spec §3.10 production decision).
- Scroll observer test: show overlay → trigger `NSScrollView.willStartLiveScrollNotification` programmatically (via posting the notification from harness with proper user-info) → assert overlay dismissed. Skip if seed doc fits one viewport — extend doc with extra content to force scrollability.
- **Phase 4 not commitable until Tab cycle + scroll-commit green.**

---

## Phase 5 — Modal popout

**Files (new):**
- `Sources/Editor/Renderer/Tables/CellEditModalController.swift`

**Files modified:**
- `Sources/Editor/LiveRenderTextView.swift` — `menu(for:with:)` override or NSMenu binding.
- `Sources/Editor/EditorContainer.swift` — wire CellEditModalController.

### Right-click menu

Override `LiveRenderTextView.menu(for event: NSEvent) -> NSMenu?`:

```swift
override func menu(for event: NSEvent) -> NSMenu? {
    // First check: is the click on a table cell?
    let cellHit = hitTestCell(at: event.locationInWindow)
    let menu = super.menu(for: event) ?? NSMenu()
    if let hit = cellHit {
        // If overlay is active on this exact cell, omit the popout item
        // (per spec §3.13 row 3).
        let alreadyEditingThisCell = coordinator?.cellEditController?.activeCell == hit
        if !alreadyEditingThisCell {
            let item = NSMenuItem(
                title: "Edit Cell in Popout…",
                action: #selector(editCellInPopoutAction(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = hit  // (rowIdx, colIdx, attachment, sourceRange)
            menu.insertItem(item, at: 0)
            menu.insertItem(NSMenuItem.separator(), at: 1)
        }
    }
    return menu
}
```

### `CellEditModalController`

```swift
final class CellEditModalController: NSObject {
    private weak var hostView: NSTextView?
    private var window: NSWindow?
    private var textView: NSTextView?
    private var activeCellRange: NSRange = NSRange(location: 0, length: 0)
    private var saveButton: NSButton?

    func openModal(forCellRange cellRange: NSRange,
                   originalContent: String,
                   rowLabel: String,
                   colLabel: String) {
        // Un-escape pipes for display.
        let displayContent = originalContent
            .replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "\\\\", with: "\\")

        // Build window — centered on key screen, ~600x400.
        // Title: "Edit Cell — Row N, Column M".
        // Content: vstack { NSTextView (scrollable) | hstack { Cancel, Save } }.
        // Save (or ⌘+Return) → applyCommit. Cancel (or Escape) → close.
        // ...
    }

    private func applyCommit() {
        guard let host = hostView,
              let storage = host.textStorage,
              let tv = textView else { return }
        let escaped = tv.string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
        storage.replaceCharacters(in: activeCellRange, with: escaped)
        // Trigger re-render via the existing renderCurrentText pathway.
        // (Production may need a coordinator hook here.)
        close()
    }

    private func close() {
        window?.close()
        window = nil
        textView = nil
    }
}
```

### Handoff (spec §3.13)

Right-click on a different cell while overlay is active:
```swift
@objc func editCellInPopoutAction(_ sender: NSMenuItem) {
    guard let hit = sender.representedObject as? CellHit else { return }
    // Commit any active overlay first.
    coordinator?.cellEditController?.commit()
    // Open modal on the right-clicked cell.
    coordinator?.cellEditModalController?.openModal(...)
}
```

**Phase 5 test gate (automated):**
- Add harness actions: `open_modal_at_table_cell`, `set_modal_text`, `commit_modal`, `cancel_modal`. `dump_state.modal` block: `{ active, cellRangeLocation, cellRangeLength, content }`.
- Open modal on a body cell → assert `dump_state.modal.active == true` and content matches. Commit with new text → assert source updated, modal dismissed. Open + cancel → assert source unchanged.
- Pipe round-trip: open modal on a cell whose source contains `\|` → assert `modal.content` shows literal `|` (un-escaped). Edit + commit → assert `\|` round-tripped back into source.
- Handoff test: show overlay on cell A → open modal on cell B → assert overlay was committed AND modal active on B.
- Right-click on cell A while overlay on A is active → assert "Edit Cell in Popout…" item is OMITTED from menu (or grayed). (Verified via inspecting the menu programmatically — production exposes `menu(for:)` for tests.)
- **Phase 5 not commitable until modal lifecycle + handoff green.**

---

## Phase 6 — Manual test plan + COMPLETE doc + roadmap + tag

### Manual test plan

`docs/current_work/testing/d13_cell_edit_overlay_manual_test_plan.md` — sections:

- **A. Overlay show/commit core** — single-line cell, type, commit on Enter / Tab / click-out / Escape.
- **B. Wrapped cell** — click on visual line 2 of a wrapped cell → caret on line 2 at click x. (PRIMARY case.)
- **C. Tab nav** — Tab/Shift+Tab cycle cells across rows, header excluded, boundary dismiss.
- **D. Active-cell border** — visual confirm 2pt accent border, text position invariant active vs inactive.
- **E. Scroll-while-active** — scroll commits + dismisses.
- **F. Empty cell** — click empty cell, type, commit; cell renders with new content.
- **G. Modal popout** — right-click → menu has "Edit Cell in Popout…"; opens centered modal; Save → splice; Cancel → discard; ⌘+Return = Save, Escape = Cancel.
- **H. Handoff** — right-click on cell B while overlay on cell A: A commits, modal opens on B.
- **I. Reveal mode interaction** — double-click drops to source mode; single-click in revealed row uses default NSTextView path (no overlay).
- **J. Regression** — D8 grid, D9 scroll-to-line, D10 line numbers, D11 CLI, D12 cell-boundary nav (no overlay) all work.
- **K. Engineering standards** — `grep -r '\.layoutManager' Sources/` clean.

### COMPLETE doc

`docs/current_work/stepwise_results/d13_cell_edit_overlay_COMPLETE.md` — files modified/created, key findings (CT math, Tab anchor pattern, edit-time spillover), deviations from spec/plan, links to spike findings.

### Roadmap update

`docs/roadmap_ref.md`:
- D13 row → ✅ Complete — 2026-04-XX
- New change-log entry summarizing.

### Tag

`v0.2` after D13 ships green on `main`.

**Phase 6 test gate (automated):**
- All Phase 1–5 harness tests run as a final regression suite against the v0.2 candidate build.
- D8/D9/D10/D11 regression test sequence (existing — no D12 path yet but D8.1 reveal-on-double-click should be in regression).
- D12 cell-boundary arrow nav between cells (without overlay active) — regression case.
- Engineering-standards: `grep -r '\.layoutManager' Sources/` returns nothing new beyond what existed pre-D13.
- **Phase 6 not commitable until full automated regression green.**

---

## Verification checklist

- [ ] Phase 1: `TableLayout.cellLocalCaretIndex` lands; unit + harness tests green.
- [ ] Phase 2: `CellEditOverlay` + `CellEditController` build green; lifecycle round-trip + visual baseline green.
- [ ] Phase 3: synthetic-click → overlay → caret position chain green; `snapCaretToCellContent` removed.
- [ ] Phase 4: Tab nav cycle (incl. cross-row + boundary dismiss + header exclusion) + scroll-commit green.
- [ ] Phase 5: modal lifecycle + handoff rules green.
- [ ] Phase 6: manual test plan written; each section passed by CD; full automated regression suite green; COMPLETE doc landed; roadmap flipped; tag pushed.
- [ ] `grep -r '\.layoutManager' Sources/` clean (engineering-standards §2.2).
- [ ] D8 / D9 / D10 / D11 / D8.1 reveal / delimiter reveal / D12 cell-boundary nav regressions: none.

---

## Risks

1. **D12's `CellSelectionDataSource` interactions** — D12 routes single-click hit-tests through `lineFragmentRangeForPoint`. With the overlay path active, that data source is still installed but the overlay's `mouseDown` intercepts before the data source matters. Verify NSTextView still consults the data source for non-mouseDown selection navigation (e.g., arrow keys when overlay is NOT active). Regression-test D12's cell-boundary arrow nav after Phase 3.

2. **Re-render destroys layout instances** (spike finding). Tab nav uses source-position anchors. Other future code that bridges renders must follow the same pattern.

3. **Scroll observer subscription leaks** — the controller adds an observer per show; teardown must remove it cleanly. Use `removeObserver(self)` in teardown to be defensive.

4. **Modal handoff edge case** — if user commits modal while overlay is also open on a different cell (race condition: overlay on cell A, user right-clicks cell B fast, somehow modal opens before A's commit fires), resulting state could have both active. Mitigation: `commit()` is synchronous; menu action chain commits A then opens modal on B.

5. **Right-click on header cell** — spec §3.10 says header cells are excluded from Tab cycle. But right-click ON a header cell should still be able to open the popout. Decision: yes, allow popout on headers (modal is the universal escape). Update spec if not already clear. (Currently §3.12 says "right-click on a cell" — implicitly inclusive of headers.)

6. **CellEditModalController Save without changes** — if user opens modal, makes no edits, hits Save. Source-splice is `replaceCharacters(in: range, with: sameContent)` — no-op semantically but generates an undo entry. Acceptable; matches Word behavior.

7. **`renderCurrentText` re-entry** — production's renderer may have re-entry guards. Verify that `commit()`'s call into the re-render path doesn't trigger a recursive overlay-show during rendering.

---

## Out of scope for D13

- Inline markdown rendering inside cells (deferred per Q8 — future deliverable; modal popout will be the rendering+toolbar surface).
- Multi-cell drag-select (§3.8 V1: out of scope; future polish).
- Auto-fallback to modal on unhandled content types (V1.x; needs inline-markdown parser to detect).
- Modal handoff for two simultaneous modals (modal is application-modal in V1).
- Inline image attachments inside cells (modal will eventually edit; overlay won't handle).
