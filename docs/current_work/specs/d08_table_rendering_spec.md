# D8: GFM Table Rendering — Specification

**Status:** Draft
**Created:** 2026-04-23
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D1 (TextKit 2 hosting), D2 (renderer pattern, DocumentType registry), D4 (mutation primitives — not extended here, but same AST boundary)
**Traces to:** `docs/vision.md` Principle 3 (markdown today, structured formats tomorrow — tables are the first structured block we render visually rather than as styled text); `docs/competitive-analysis.md` (Typora = grid-replace-source; iA Writer = aligned source; md-editor's live-render philosophy points to a hybrid of the two); `docs/engineering-standards_ref.md` §2.2 (no `.layoutManager` access)

---

## 1. Problem Statement

Markdown source files in our dogfood corpus (`docs/`) use GFM pipe-tables for roadmap matrices, dimension tables, and stack decision tables. Today md-editor renders these as plain paragraph text — the pipes and dashes show through verbatim, nothing aligns, and the structure a reader needs isn't visible until they mentally parse the pipes.

swift-markdown parses GFM tables natively (`Markdown.Table` / `TableHead` / `TableBody` / `TableRow` / `TableCell` with a `columnAlignments: [ColumnAlignment?]` array). The renderer at `Sources/Editor/Renderer/MarkdownRenderer.swift` currently dispatches only Heading, Strong, Emphasis, InlineCode, Link, and CodeBlock; any Table node falls through the `default` branch and keeps the body font.

D8 adds a **real** table rendering — column-aligned, header-weighted, header-separated — while preserving the live-render philosophy already in place for delimiters (cursor-on-line reveals source; cursor-off presents formatted output).

---

## 2. Requirements

### Functional — rendering (cursor outside the table range)

- [ ] A GFM pipe-table in the source is detected as a `Markdown.Table` node and rendered as a **visual grid**:
  - Columns are width-aligned across rows (widest cell in each column sets the column width).
  - Header row (`TableHead`) uses `Typography.boldFont` (or heading-style equivalent).
  - A visible horizontal separator sits between the header row and the body.
  - Per-column alignment from `Table.columnAlignments` maps to leading / center / trailing text alignment within each cell.
  - Pipe characters (`|`) in the source are **not visible** when the cursor is outside the table range — rendered as column separators (a thin vertical rule or as inter-column whitespace; see Design §3.3).
  - The separator-row dashes (`|---|---|`) are hidden.

### Functional — edit mode (cursor inside the table range)

- [ ] When the cursor enters the table's source range, the table reveals as **pipe-delimited source text** — the same reveal-on-line behavior that delimiters already use (`Typography.revealScopeKey` attribute). Editing the source feels identical to editing any other markdown block.
- [ ] Cursor leaving the table range returns the view to the rendered-grid form.
- [ ] Reveal scope covers the **whole table** — cursor on any row reveals the entire block, not just that row. (A partial reveal would leave the grid in a half-rendered state mid-edit; engineering decision is to match CodeBlock's whole-block reveal pattern.)

### Functional — alignment syntax

- [ ] All three GFM alignment markers are honored:
  - `:---` → leading alignment
  - `:---:` → center alignment
  - `---:` → trailing alignment
  - `---` (no colon) → default (leading)

### Functional — malformed tables

- [ ] A "table" that swift-markdown didn't parse as a `Markdown.Table` (malformed — uneven column counts, missing separator row, etc.) is **not** special-cased. It renders as whatever swift-markdown gave us (likely a Paragraph), which the renderer already handles via the default branch.
- [ ] A `Markdown.Table` with zero rows renders as empty (degenerate but not a crash).

### Non-functional

- [ ] **Standards §2.1** — no new interactive views introduced by D8, so no new `accessibilityIdentifier` entries expected. If the Design decision is to use an `NSTextAttachment`-backed view (see §3.3 Approach B), the attachment view must carry an `accessibilityLabel` describing the table ("Table, N columns, M rows").
- [ ] **Standards §2.2** — no `.layoutManager` access. D8 must use TextKit 2 (`NSTextContentManager` / `NSTextLayoutManager`) for any custom layout work, or stay within NSParagraphStyle / NSAttributedString attributes.
- [ ] **Standards §2.3** — no new keyboard shortcuts introduced by D8.
- [ ] **Standards §2.4** — not applicable; tables are a renderer concern, not an external command surface.
- [ ] **Performance** — a document with up to 20 tables of up to 30 rows × 10 columns renders within the same frame-budget as a document of equivalent total text length without tables. Measured subjectively; no regression on typical dogfood docs.
- [ ] **Live reflow** — typing inside a table (edit mode) does not redraw the grid on every keystroke. The grid only re-renders when the cursor leaves the table range, same as the existing reveal-scope flow.

### Functional — dogfooding validation

- [ ] End of D8: opening `docs/roadmap_ref.md` (and other doc files containing pipe-tables) in md-editor shows a proper visual grid where today only raw pipe-source is visible. The dimension-table in `docs/stack-alternatives.md` reads as a table, not as a wall of pipes.

---

## 3. Design

### 3.1 Approach

Three rendering strategies were considered. The recommendation is **Approach C** (hybrid), which matches md-editor's live-render philosophy already established for delimiters and code-block fences.

**Approach A — aligned source (rejected).** Style the pipes subtly and use `NSParagraphStyle` tab stops to column-align the text. Problem: tab stops align text *after* tab characters, not after pipes. Would require rewriting the source text or inserting invisible tabs, both of which break the source-is-truth model. Rejected.

**Approach B — NSTextAttachment grid (partial reject).** Replace each table's source with an `NSTextAttachment` whose view is a grid (NSStackView or NSTableView-lite). Full visual control, but the source text is still present in storage so editing becomes non-obvious — you'd have to click through the attachment to reach the source. Rejected as the *primary* mode for the same reason D4's reveal-scope model chose in-place delimiter reveal over modal editing: md-editor is a text editor, not a structured-document editor.

**Approach C — reveal-scoped grid (recommended).** Use the same reveal-scope mechanic that CodeBlock already uses (`Typography.revealScopeKey`):
- **Cursor outside the table range:** source is styled as a grid — pipes and separator-row characters are hidden via attributes (matching background color, zero-width foreground, or struck with `.foregroundColor = .clear` and offset via paragraph indent); cells are visually column-aligned via an `NSTextAttachment` per row OR (preferred — see §3.3) a per-row paragraph style built from measured column widths using tab-character insertion **into the attributed string only** (not the source).
- **Cursor inside the table range:** reveal-scope kicks in exactly as for code blocks today. Source pipes show through. The reveal-scope range is the full `Table` node's NSRange.

### 3.2 Module layout

```
Sources/Editor/Renderer/
├── MarkdownRenderer.swift            (existing — add Table dispatch)
└── Tables/                           (new sub-folder for D8 table code)
    ├── TableRenderer.swift           Top-level: walk Table → produce AttributeAssignments + SyntaxSpans
    ├── TableMeasurement.swift        Column-width measurement from cell content
    ├── TableAttributes.swift         NSAttributedString attribute construction per cell / per row
    └── TableRevealScope.swift        Helpers for marking the whole-table reveal-scope range

Sources/Support/
└── Typography.swift                  (existing — add table-specific typography constants:
                                       tableHeaderFont, tableSeparatorColor, tableCellInset)
```

### 3.3 Rendering strategy (Approach C details)

Per-row processing on visit of each `TableRow`:

1. **Measure column widths.** Walk the full `Table` first to collect `max(cellStringWidth)` per column — use `NSAttributedString.size()` or `NSLayoutManager`-free `.boundingRect` on the cell content attributed string. Store as `[CGFloat]`.
2. **Build per-row paragraph style.** Create `NSMutableParagraphStyle` with `tabStops` placed at cumulative column boundaries. Per-column alignment (from `columnAlignments`) maps to tab-stop alignment (`NSTextTab.TextTabType` equivalents in `NSTextTab.columnTerminators:location:`).
3. **Rewrite the visible rendition (attribute-only).** Source pipes remain in the buffer; their visual rendition is made invisible by applying `.foregroundColor = NSColor.textBackgroundColor` (or `alphaValue=0` equivalent) + zero-width kerning on pipe characters only. Between cells, insert a tab via `.kern` or `NSAttachmentAttribute` spacers to push the next cell to its tab stop. **If attribute-only cell-positioning proves infeasible on TextKit 2 without touching the layout manager**, fall back to an `NSTextAttachment` that renders the whole `Table` block as a custom view (Approach B) for the cursor-outside state only, preserving the source in the buffer.
4. **Header row.** Apply `Typography.tableHeaderFont` (bold at body size) to the header row's range. Add a bottom-border attribute (custom attribute key + TextKit 2 drawing) or insert a zero-height paragraph with a `.paragraphSpacingBefore` and a horizontal rule via `.strikethroughStyle` on a dedicated line (exploratory — final technique chosen in implementation).
5. **Reveal scope.** Emit a single `AttributeAssignment` with `Typography.revealScopeKey = NSValue(range: tableRange)` spanning the entire Table node. Cursor inside → all hidden-pipe attributes suppressed, raw pipes become visible, header bold reverts. (The existing cursor-on-line tracker handles the reveal swap.)

### 3.4 AST dispatch

Extend `RenderVisitor.walk` in `MarkdownRenderer.swift`:

```swift
case let table as Table: visitTable(table)
```

`visitTable` delegates to `TableRenderer.render(table:into: visitor)`, which appends `AttributeAssignment`s and `SyntaxSpan`s just like the other visitors. Children of the Table are **not** walked further — TableRenderer owns the entire sub-tree.

### 3.5 Interaction with CursorLineTracker

The existing `Sources/Editor/Renderer/CursorLineTracker.swift` handles reveal-scope toggling. It looks up the reveal-scope attribute at the cursor line and reverts any `delimiter` tagging within that scope. For D8, the same mechanism handles the table's whole-block reveal — but the reveal must revert **more than delimiter styling**: the hidden pipes, the inserted tab spacing, and the header font all need to flip back to source-faithful styling.

The tracker will need to distinguish a "table reveal" from a "delimiter reveal" so it knows which attributes to swap. Options:
- New attribute key `Typography.tableRevealScopeKey` (preferred — keeps table concerns isolated).
- Overload `revealScopeKey` with a companion `revealKind` attribute.

D8 picks the first; spec open-question #2 below.

---

## 4. Success Criteria

- [ ] Opening `docs/roadmap_ref.md` in md-editor shows every table as a column-aligned grid with bold header row and visible header separator. Pipes are not visible.
- [ ] Clicking into any cell of a rendered table reveals pipe-delimited source spanning the full table block. Typing edits the source. Cursor leaving the table re-renders the grid.
- [ ] All three GFM alignment markers render correctly (verify with a purpose-built test fixture `docs/fixtures/tables-alignment.md`).
- [ ] A malformed pipe-pattern that swift-markdown parses as Paragraph still renders as plain paragraph text (no crash, no partial table chrome).
- [ ] All existing D1-D6 tests still pass. D8 adds a renderer-unit test for a 3×3 GFM table + a UITest that places the cursor inside and outside a table and asserts the reveal flip.
- [ ] No new `.layoutManager` references (grep confirms).
- [ ] Performance — dogfood session on `docs/` workspace shows no perceivable lag scrolling or opening files with tables.

---

## 5. Out of Scope

- **Editing tables as a structured UI.** No click-to-edit cells, no "add row / add column" toolbar. Edit mode is pipe-delimited source, same as any other block. A future deliverable could layer on structured editing.
- **Mutation toolbar integration for tables.** No "Insert Table" button. Manual typing of the GFM syntax is the entry path at D8.
- **HTML tables.** Only GFM pipe-tables (what swift-markdown's `Table` node represents) are handled.
- **Merged cells, nested tables, block elements inside cells.** swift-markdown doesn't model these for GFM tables; D8 follows the AST shape it's given.
- **Column resizing via drag.** All column widths are content-measured, not user-adjusted.

---

## 6. Open Questions

- [ ] **Q1:** Is attribute-only pipe-hiding + tab-stop column alignment achievable on TextKit 2 without layoutManager access? Implementation spike will answer this. If not, fall back to `NSTextAttachment`-backed grid per §3.3 step 3.
- [ ] **Q2:** New `tableRevealScopeKey` attribute vs. reusing `revealScopeKey` with a kind discriminator. Spec picks the first; revisit if the tracker ends up with duplicated logic.
- [ ] **Q3:** Should the header-row separator be a drawn horizontal rule (custom TextKit 2 drawing) or an attribute-only effect (e.g., bottom-border on header cells via `.strikethroughStyle` on a trailing whitespace line)? Both work; the first looks better, the second is cheaper. Implementation chooses.
- [ ] **Q4:** Reveal-scope covers the whole table — confirmed (matches CodeBlock). Leaving this tracked in case UX testing surfaces a desire for per-row reveal.

---

## 7. Findings to capture during implementation

Follow the D6 pattern — every non-obvious gotcha surfaced during implementation gets documented in the D8 COMPLETE doc. Expected categories:
- TextKit 2 layout-fragment customization patterns (this is likely the first deliverable to need them).
- swift-markdown `Table` AST edges (e.g., how `columnAlignments` is provided when the separator row omits alignment markers).
- Reveal-scope tracker edits required to support a second reveal-kind.
