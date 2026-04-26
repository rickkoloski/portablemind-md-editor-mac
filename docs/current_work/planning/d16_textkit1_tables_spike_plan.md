# D16 Plan — TextKit 1 Tables Spike

**Spec:** `docs/current_work/specs/d16_textkit1_tables_spike_spec.md`
**Created:** 2026-04-26

---

## 0. Approach

Standalone Swift Package app at `spikes/d16_textkit1_tables/`,
mirroring the layout of `spikes/d13_overlay/`. No production code
edits. App launches, validates the four scenarios, writes
`FINDINGS.md` + `STATUS.md`.

Each phase is independently runnable (`./run.sh phase=N`) and
GREEN/YELLOW/RED gated. Stop on first RED — that answers the
question.

---

## Phase 1 — Project skeleton

Files:
- `Package.swift` — exec target named `D16Spike`, deps: none
  (Foundation + AppKit are platform).
- `Sources/D16Spike/main.swift` — `NSApplication.shared`,
  programmatic window with content NSScrollView + NSTextView
  configured for TK1 (no TK2 opt-in).
- `Sources/D16Spike/Doc.swift` — hard-coded markdown string with
  one table (4 cols, 12 body rows, one row's text intentionally
  long enough to wrap), plus 100 lines of plain text below.
- `run.sh` — `swift run D16Spike`.

DOD: app launches, shows blank text view, no crashes.

---

## Phase 2 — Render the table

The crux. Build the attributed string by hand:
- Body text → `NSAttributedString` with paragraph styles.
- Table region → for each cell: `NSAttributedString` with
  `NSParagraphStyle` whose `textBlocks` is `[NSTextTableBlock]`
  pointing into a single shared `NSTextTable`.
- `NSTextTable.numberOfColumns = 4`,
  `collapsesBorders = false`, `hidesEmptyCells = false`.
- Each `NSTextTableBlock` configured with row/col indices,
  `setBorderColor(.separator)`, `setWidth(1, type: .absolute,
  for: .border)`, padding, etc.

Set the assembled string on `textView.textStorage`. Verify TK1
draws the grid natively.

DOD:
- Open app → table renders below the initial viewport (since
  there's plain text above it).
- Scroll into the table → all rows visible, grid lines correct,
  no missing rows. **(Scenario 1 GREEN if TK1 handles this with
  zero custom layout code.)**
- Programmatically scroll past the table and back → still
  correct. (TK2 failed this; TK1 should be trivial.)

If RED: framework can't even render the table without help. Stop.
File spec mismatch.

---

## Phase 3 — Click-to-caret (Scenario 2)

With the table rendered:
- Click on any cell.
- Read `textView.selectedRange()` — the location should be inside
  the cell's character range, not on a paragraph-separator
  character.

How to verify "inside a cell":
- After building the attributed string, store a side table of
  `[(rowIdx, colIdx) : NSRange]` for each cell's character span.
- After click, look up which cell range contains the new
  selection. Log to FINDINGS.md.

DOD: 5 trial clicks across different cells (header, body, top
row, bottom row, wrapped cell) all resolve to a cell range.

If TK1 routes any click outside cell ranges (paragraph separator,
dead zone), document and treat as YELLOW (workable but needs
hit-test adjustment). RED only if there's no consistent way to
land in a cell.

---

## Phase 4 — Type-without-jump (Scenario 3)

- Place caret in cell (5, 1) via `setSelectedRange(...)`.
- Capture `scrollView.contentView.bounds.origin.y` as `y0`.
- `textView.insertText("xxx", replacementRange: ...)` — three
  characters.
- Capture scrollY again as `y1`.
- Assert `y0 == y1`.

Repeat with caret at the bottom of the visible area (where TK2
would auto-scroll). If TK1 handles this without our scroll
suppression hack, GREEN. If TK1 also auto-scrolls, YELLOW (we'd
need the same scroll guard we built for TK2 — not a regression
but not a clean win).

DOD: 3 typing positions tested, scroll delta documented for each.

---

## Phase 5 — Wrapped-cell click (Scenario 4)

The hardest TK2 case (wrapped cells were the original D13
motivation). For TK1:
- Identify the wrapped cell from Phase 2's data.
- The cell's content takes 2 visual lines at the configured
  column width.
- Click at coords known to be on visual line 2 (compute Y from
  the cell's known origin + first-line height).
- After click, `textView.selectedRange().location` should be in
  the latter half of the cell's character range.

This is where TK2's custom-fragment math couldn't see line 2
without our `cellLocalCaretIndex` workaround. If TK1 handles it
natively (because flowed paragraphs in cells get ordinary
glyph-run hit-testing), GREEN.

DOD: wrapped-cell click resolves to the correct half of the
cell's range. FINDINGS.md notes the exact char offset.

---

## Phase 6 — Findings + Status

Write:
- `FINDINGS.md`: per-phase GREEN/YELLOW/RED + notes + next
  questions.
- `STATUS.md`: summary verdict, recommendation (proceed with
  migration / refine spike / fall back to TK2 with reference
  prototype as guide).

If overall GREEN, we're done with the spike. The migration plan
itself is a separate triad.

---

## Risk register

| Risk | Mitigation |
|---|---|
| TK1 table API has its own quirks we don't know about | The four scenarios cover the patterns that matter; if TK1 has unrelated quirks, those surface in the migration plan, not here. |
| Wrapping behavior differs subtly between TK1's NSTextTable and CSS-style table cells | Phase 5 explicitly tests wrapping; document any deviation as a constraint, not a blocker. |
| TK1's `addLayoutManager` requirement triggers warnings or deprecation paths | Compile-clean target; if we hit deprecation warnings, note in FINDINGS but don't block on them — TK1 is still supported. |
| Spike works but can't be migrated cleanly because TK1 / TK2 have incompatible app-level patterns (e.g. `NSTextLayoutManager` types vs `NSLayoutManager`) | Out of scope for the spike; migration plan handles. |

---

## Non-goals (so they don't sneak into the spike)

- Source-reveal mode (D8.1).
- Cell-level Tab/arrow nav (D12).
- Active-cell border affordance (D13 §3.7).
- Modal popout (D13 §3.12).
- Markdown parser (just hard-coded attributed string).
- File I/O (D14).
- Multiple tables.
- Performance benchmarks.

If a spike phase produces a workable GREEN for the four canonical
scenarios using TK1, the migration plan is where we re-add each
of the above as deliberate, separately-validated work.