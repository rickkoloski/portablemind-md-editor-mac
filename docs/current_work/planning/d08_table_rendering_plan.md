# D8: GFM Table Rendering — Implementation Plan

**Spec:** `d08_table_rendering_spec.md`
**Created:** 2026-04-23

---

## Overview

Wire `Markdown.Table` into `MarkdownRenderer` via a new `Sources/Editor/Renderer/Tables/` sub-module. Render tables as column-aligned grids when the cursor is outside the block; reveal pipe-delimited source when the cursor is inside, via the existing reveal-scope mechanic.

Work is expected to surface at least one TextKit 2 layout-customization finding — this is the first deliverable to go beyond attribute styling into positional layout.

---

## Prerequisites

- [ ] Editor and renderer scaffolding unchanged since D6 end-of-session. Verify with `xcodebuild … test` smoke run before starting.
- [ ] swift-markdown `Table` AST confirmed present in the checked-out SPM checkout (`.build-xcode/SourcePackages/checkouts/swift-markdown/Sources/Markdown/Block Nodes/Tables/`). Already verified at spec time.
- [ ] Dogfood corpus contains tables to eyeball during implementation (`docs/roadmap_ref.md`, `docs/stack-alternatives.md`, `docs/portablemind-positioning.md` all have them).

---

## Implementation Steps

### Step 1: Wire Table dispatch through the renderer (stub)

**Files:** `Sources/Editor/Renderer/MarkdownRenderer.swift`

Add the case to `RenderVisitor.walk`:

```swift
case let table as Table: visitTable(table)
```

And a stub visitor:

```swift
private func visitTable(_ table: Table) {
    // D8 stub — handed off to TableRenderer in step 2
    for child in table.children { walk(child) } // temporary — walk for now
}
```

**Verify:** build green, open a tables-containing file, no crash; tables still render as today's raw-pipe source. Baseline preserved before introducing real rendering.

---

### Step 2: Introduce `Sources/Editor/Renderer/Tables/` module

**Files to create:**
- `Sources/Editor/Renderer/Tables/TableRenderer.swift`
- `Sources/Editor/Renderer/Tables/TableMeasurement.swift`
- `Sources/Editor/Renderer/Tables/TableAttributes.swift`
- `Sources/Editor/Renderer/Tables/TableRevealScope.swift`

**Files to modify:**
- `Sources/Editor/Renderer/MarkdownRenderer.swift` (delegate `visitTable` to `TableRenderer`)

Shapes:

```swift
// TableRenderer.swift
@MainActor
enum TableRenderer {
    static func render(_ table: Table,
                       into visitor: RenderVisitor) {
        let rows = TableMeasurement.extractRows(table)
        let widths = TableMeasurement.columnWidths(rows: rows)
        let alignments = table.columnAlignments
        TableAttributes.apply(
            rows: rows,
            widths: widths,
            alignments: alignments,
            into: visitor
        )
        TableRevealScope.mark(range: tableRange, into: visitor)
    }
}
```

Keep each file <150 lines; split further if a file grows. `TableMeasurement` owns column-width math; `TableAttributes` owns all NSAttributedString attribute building; `TableRevealScope` owns the reveal-scope attribute application.

---

### Step 3: Column-width measurement

**Files:** `Sources/Editor/Renderer/Tables/TableMeasurement.swift`

Walk the Table → TableHead + TableBody → TableRow → TableCell. For each cell, build an NSAttributedString of its content using the body font, call `.size()` to measure. Keep the per-column max width.

**Gotcha:** cell content can contain inline formatting (Strong, Emphasis, InlineCode). Approximate measurement using the body font on the plain-text content is acceptable at D8 — inline formatting typically doesn't shift widths enough to break alignment. Note this in the COMPLETE doc if it turns into a finding.

---

### Step 4: Attribute-only grid rendering — spike first

**Files:** `Sources/Editor/Renderer/Tables/TableAttributes.swift`

This is the step where open-question Q1 gets answered. Approach:

1. Build an `NSMutableParagraphStyle` per row with `tabStops` at cumulative column boundaries. Per-cell tab-stop alignment derived from `Table.ColumnAlignment`.
2. Attempt to hide pipe characters via `.foregroundColor = NSColor.textBackgroundColor` (background-matched) + `.kern` adjustment so the glyph consumes zero advance. Test whether this actually produces the visual of a tab-aligned grid.
3. If step 2 doesn't converge visually, fall back to `NSTextAttachment` per row (Approach B from spec §3.1): each row becomes a single attachment containing a horizontally-composed NSView. Source stays in storage; the attachment provides the rendered chrome.

**Decision point:** spike for no more than 2 hours on the attribute-only path. If it doesn't work, switch to NSTextAttachment. Document the finding.

**Header styling:** header rows get `Typography.tableHeaderFont` (bold at body size). Header separator is a horizontal rule — implementation choice between custom TextKit 2 drawing and an attribute-only bottom-border effect.

---

### Step 5: Reveal-scope for the whole table

**Files:** `Sources/Editor/Renderer/Tables/TableRevealScope.swift`, `Sources/Editor/Renderer/CursorLineTracker.swift`

Apply a new attribute key `Typography.tableRevealScopeKey` on the entire table's NSRange with `NSValue(range: tableRange)` payload (same shape as the existing `revealScopeKey`).

Extend `CursorLineTracker` to recognize the new key. When the cursor is on a line within a table-reveal range, revert:
- Pipe-hiding attributes (re-show pipes)
- Header bold (if cursor is in the header row)
- Column tab-stop spacing (revert to natural source paragraph style)

The reveal **must match the existing pattern exactly** — same reveal/restore symmetry, no new edge cases. If CursorLineTracker needs refactoring to cleanly support two reveal kinds, do so in this step.

---

### Step 6: Typography additions

**Files:** `Sources/Support/Typography.swift`

Add:
- `tableHeaderFont: NSFont` — body size, bold
- `tableHeaderSeparatorColor: NSColor` — a subdued separator color
- `tableCellInset: CGFloat` — horizontal padding between column content and the next tab stop
- `tableRevealScopeKey: NSAttributedString.Key` — new key for table-specific reveal scope

---

### Step 7: Unit test — renderer output

**Files:** `MdEditorTests/TableRendererTests.swift` (new)

Given a 3×3 GFM table source string, assert the `RenderResult.assignments` contain:
- Bold font on the header row range
- `tableRevealScopeKey` attribute spanning the full table
- At least one paragraph-style attribute per body row

Don't assert on exact NSAttributedString glyph positioning — too brittle.

---

### Step 8: UITest — reveal round-trip

**Files:** `UITests/TableRevealTests.swift` (new)

Launch the app, open a fixture markdown file with a single table. Assert (via `.firstMatch` query per engineering-standards §2.1):
- When cursor is placed in the prose before the table, the pipes are not part of the visible accessibility text tree OR an accessibility label for the table block reports "Table, N columns, M rows" (implementation-dependent; pick one).
- When cursor is clicked into the table's line range, the pipes are visible in the accessibility text.

If the attribute-only pipe-hiding approach doesn't expose well to UITest, assert via `mdeditor://` command surface or via the content-manager snapshot, not via pixel comparison.

---

### Step 9: Dogfood validation

Run `./scripts/md-editor apps/md-editor-mac/docs/`. Open `roadmap_ref.md`, `stack-alternatives.md`, `portablemind-positioning.md`, `competitive-analysis.md`. Visually confirm every pipe-table renders as a grid. Click into each table to confirm reveal/restore works. Screenshot each for the COMPLETE doc.

---

## Testing

### Manual Testing
1. Open `docs/roadmap_ref.md`. All tables render as grids.
2. Click inside each table. Pipes reveal. Type a character. Click out. Grid re-renders with the change.
3. Open a file with a malformed pipe sequence (create `docs/fixtures/malformed-table.md` with a separator-row missing). Confirm renders as plain paragraph, no crash.
4. Open an empty file. Confirm no regression in empty-state handling.
5. Open a very large table (30 rows × 10 columns). Confirm no perceptible lag.

### Automated Tests
- [ ] `TableRendererTests.swift` passes.
- [ ] `TableRevealTests.swift` passes.
- [ ] Existing `MutationToolbarTests` and prior-D test suites still pass (no renderer regression).

---

## Verification Checklist

- [ ] All implementation steps complete.
- [ ] Manual dogfood testing passes across the four target doc files.
- [ ] Automated tests pass.
- [ ] `grep -r '\.layoutManager' Sources/` returns no new hits.
- [ ] No new `accessibilityIdentifier`s skipped — if the `NSTextAttachment` fallback is used, the attachment carries an `accessibilityLabel`.
- [ ] Findings recorded in `docs/current_work/stepwise_results/d08_table_rendering_COMPLETE.md` — at minimum the Q1 outcome (attribute-only vs. attachment-backed).
- [ ] D8 marked complete in `docs/roadmap_ref.md`.

---

## Notes

- This is the first D that pushes into positional layout, not just attribute styling. Budget for one round of "hit a wall, pivot to NSTextAttachment" — the spec is designed to accommodate either outcome.
- swift-markdown's `Table.columnAlignments` can be shorter than the actual column count if trailing columns use default alignment. Guard against index-out-of-bounds by treating missing entries as `.none`.
- The reveal-scope plumbing in CursorLineTracker is the cleanest point of risk for regression — existing delimiter reveal behavior must not change. If CursorLineTracker touching causes delimiter-reveal tests to go yellow, the refactor is wrong; revert and try a narrower change.
- Finding-capture discipline from D6 applies: every dead-end pivot and every non-obvious gotcha gets a numbered finding in the COMPLETE doc.
