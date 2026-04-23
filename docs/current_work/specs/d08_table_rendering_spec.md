# D8: GFM Table Rendering — Specification

**Status:** Draft (revised 2026-04-23 evening — Approach D + CellRenderer extensibility)
**Created:** 2026-04-23
**Revised:** 2026-04-23 evening
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D1 (TextKit 2 hosting), D2 (renderer pattern, DocumentType registry)
**Traces to:** `docs/vision.md` Principle 3 (markdown today, structured formats tomorrow — tables are the first structured block we render as structure, not styled text); `docs/competitive-analysis.md`; `docs/engineering-standards_ref.md` §2.2 (no `.layoutManager`)

---

## 1. Problem Statement

Markdown source in our dogfood corpus uses GFM pipe-tables for roadmap matrices, stack-decision tables, and dimension matrices. Today md-editor renders these as plain paragraph text. A V1 attempt (pipe-hiding via `syntaxRoleKey` delimiters, separator-row hidden, header bold, reveal-scope) was implemented and reverted the same evening — without real column alignment, hiding the pipes actually made tables *less* legible (the pipe glyphs were doing the visual work of "this is a table"). A real implementation must give structure, not just styling.

## 2. Design change — Approach D (NSView-inline rendering)

The earlier spec outlined three approaches (A: aligned source with tab stops, B: `NSTextAttachment` grid, C: reveal-scoped attribute-only). All three have fatal weaknesses for a durable product:

- **A** depends on monospace source alignment + tab stops not naturally consuming pipes.
- **B's classic form** requires U+FFFC in storage — modifies source, breaks the source-is-truth model.
- **C (attribute-only)** can't handle wrapped long cells, depends on monospace body font, and produces reveal-time visual artifacts.

**Approach D — inline NSView rendering without source modification** is the revised target. It's what TextKit 2 was designed for. Three sub-variants exist; the right one is picked in-spike (§6 below):

- **D1 — `NSTextAttachmentViewProvider` (classic attachment path).** Requires U+FFFC; likely rejected unless we can suppress the source text in parallel.
- **D2 — Custom `NSTextLayoutFragment` via `NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)`.** Substitute a custom fragment for the table's range. TextKit 2 draws the custom fragment in place of the normal paragraph layout. No storage modification.
- **D3 — Paragraph-style line-height reservation + parallel NSView overlay.** Force the table's source range to have a large `minimumLineHeight` (reserves vertical space), make the source text visually invisible via `syntaxRoleKey` delimiter collapse, and place a custom NSView over the reserved space positioned via `NSTextLayoutManager` geometry query. No storage modification.

**D2 is preferred** if it works cleanly on TextKit 2 across the macOS versions we target. **D3 is a documented fallback** with more moving parts but fewer API dependencies.

## 3. Requirements

### Functional — rendering (cursor outside the table range)

- [ ] A GFM `Markdown.Table` is detected and rendered as a **visual grid** via the chosen Approach D variant.
- [ ] Columns are width-aligned. Cells with long content wrap within their column (not across columns).
- [ ] Header row gets bold + a visible horizontal separator below it.
- [ ] Per-column alignment from `Table.columnAlignments` is honored (leading / center / trailing).
- [ ] Cell content is rendered via a **pluggable `CellRenderer` protocol** (see §4). Default renderer handles markdown-formatted cell content. Future renderers can extend.
- [ ] Source text is not modified. `document.source` == what's on disk, always.

### Functional — edit mode (cursor inside the table range)

- [ ] When the cursor enters the table's source range, the grid dissolves and pipe-delimited source becomes visible — same reveal-on-line pattern that delimiters already use.
- [ ] Cursor leaves → grid re-renders.
- [ ] Reveal covers the whole table (matches CodeBlock's whole-block reveal pattern).

### Functional — alignment + malformed + edge cases

- [ ] All three GFM alignment markers honored (`:---`, `:---:`, `---:`).
- [ ] Malformed pipe-patterns that swift-markdown doesn't parse as `Markdown.Table` render as whatever swift-markdown does give us (usually Paragraph) — no special-casing.
- [ ] Zero-row tables render as empty (degenerate but not a crash).

### Non-functional

- [ ] Standards §2.2 — TextKit 2 only. No `.layoutManager`.
- [ ] Standards §2.1 — any embedded NSView gets `accessibilityLabel` like "Table, N columns, M rows" + per-cell accessibility.
- [ ] Performance — 20 tables × 30 rows × 10 cols should render inside the same frame-budget as equivalent prose. Subjective measurement.
- [ ] Proportional-body-font portable. Column alignment must not depend on monospace glyph advance.

### Functional — dogfood validation

- [ ] `docs/roadmap_ref.md`, `docs/stack-alternatives.md`, and `docs/portablemind-positioning.md` all render tables as grids. The roadmap's "D# / Deliverable / Status" table reads as a grid with wrapped long cells, not as raw pipes, not as a V1-style run-on paragraph.

## 4. CellRenderer extensibility

Pluggable cell rendering is a first-class design point (CD's call, 2026-04-23 evening).

```swift
@MainActor
protocol CellRenderer {
    /// Render the given cell into an NSView. The caller provides the
    /// cell's desired width; the renderer returns a view sized to its
    /// content (the caller handles height summing for the row).
    func renderCell(_ cell: Markdown.Table.Cell,
                    width: CGFloat,
                    alignment: Markdown.Table.ColumnAlignment?) -> NSView
}

enum CellRendererRegistry {
    static let `default`: CellRenderer = MarkdownCellRenderer()
    /// Future: @MainActor func register(_: CellRenderer, for: CellKind)
    /// where CellKind is derived from cell content (e.g., `[x]` → checkbox).
}
```

The default `MarkdownCellRenderer` renders cell content as attributed text using the existing `MarkdownRenderer` AST walk on the cell's children — so bold/italic/link inside cells work automatically.

Future extensions (not D8):
- Checkbox renderer (`[x]` / `[ ]` becomes a real checkbox control).
- Status-badge renderer (known status strings become colored chips).
- Link-as-button renderer.

## 5. Module layout

```
Sources/Editor/Renderer/Tables/
├── TableRenderer.swift        Entry point — visitor method called from MarkdownRenderer
├── TableLayout.swift          Column-width computation + row-height summing
├── TableGridView.swift        Custom NSView that draws the grid (borders, separator)
├── CellRenderer.swift         Protocol + default MarkdownCellRenderer
└── TableFragment.swift        (D2 variant) custom NSTextLayoutFragment
                          OR
    TableOverlayController.swift (D3 variant) overlay positioning controller
```

Exact file set depends on which D-variant the spike validates.

## 6. Spike plan — D8 Phase 1

**Objective:** prove that inline NSView rendering at a specified text range is achievable on TextKit 2 **without modifying storage**. Budget: 60–90 min.

**Test harness:** create a minimal scratch SwiftUI view with an NSTextView containing plain markdown text plus one known table. Attempt each D-variant in isolation:

1. **D2 spike — custom NSTextLayoutFragment.**
   - Set `textContentStorage.delegate` to a controller that returns a custom paragraph for the table's range.
   - Custom fragment's `draw(at:in:)` fills a red rectangle of known size.
   - Verify: scrolling keeps the rect at the right place; surrounding text flows correctly; no source modification.

2. **D3 spike — paragraph-style line-height reservation + overlay.**
   - Apply `NSMutableParagraphStyle` with large `minimumLineHeight` to the table's source range.
   - Apply `syntaxRoleKey = delimiter` to the source chars so they collapse invisibly.
   - Query `NSTextLayoutManager` for the table range's rectangle.
   - Place a red NSView at that rectangle inside the NSScrollView's document view.
   - Verify: view stays aligned on scroll, resize, text edits elsewhere.

3. **If both work, prefer D2** (no parallel view hierarchy; TextKit 2 native).
4. **If only D3 works, spec D3** and accept the overlay management complexity.
5. **If neither works tonight**, stop, document what failed, revise spec, and try tomorrow.

## 7. Success Criteria

- [ ] Spike validates D2 or D3 — spec's implementation path is committed with evidence.
- [ ] Full D8 implementation: `docs/roadmap_ref.md` tables render as grids with bold header, separator, column alignment, wrapped long cells, default cell renderer using attributed markdown.
- [ ] Cursor enters any table → grid dissolves to pipe source. Cursor leaves → grid re-renders.
- [ ] CellRenderer protocol in place with the default implementation only (future renderers unblocked but not built).
- [ ] All prior D1–D11 tests still pass; no new `.layoutManager` refs.

## 8. Out of Scope

- Structured cell editing (click-to-edit cell as a form field). Edit mode is pipe-delimited source.
- Insert-Table toolbar button.
- Merged cells, nested tables, block-level content in cells (swift-markdown doesn't model these for GFM).
- Column resizing via drag.
- Any CellRenderer beyond the default markdown-cell renderer.

## 9. Open Questions

- **Q1 (spike-answered):** D2 custom fragment vs. D3 overlay — pick via spike.
- **Q2:** How does reveal integrate with the chosen variant? For D2 — the custom fragment is conditional on a `tableState = .grid | .source` attribute; `CursorLineTracker` toggles. For D3 — the overlay's `isHidden` is toggled by a selection observer; source attributes flip to non-collapsed on reveal. Pick in-spike.
- **Q3:** Long cells that wrap — how does the grid layout handle cells whose desired width exceeds viewport / available? Recommendation: wrap inside the cell, grow row height.
- **Q4:** CellRenderer dispatch — is the selection of renderer static (one renderer per column) or dynamic (inspect each cell's content)? Start static (one-per-column); content-sensing is a future extension.

## 10. Findings to capture

- Which D-variant worked, with code pattern.
- TextKit 2 gotchas (expected: at least one `clipsToBounds`-class surprise).
- Reveal-integration edge cases.
- Any cell-rendering artifacts (e.g., cells with inline code's grey background leaking through cell borders).
