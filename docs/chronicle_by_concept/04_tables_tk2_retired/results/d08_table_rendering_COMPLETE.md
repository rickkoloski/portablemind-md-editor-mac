# D8: GFM Table Rendering — COMPLETE (grid rendering)

**Shipped:** 2026-04-23 evening
**Spec:** `docs/current_work/specs/d08_table_rendering_spec.md` (revised this session to Approach D)
**Follow-on:** D8.1 for reveal-on-caret source mode (scoped separately — see `d08_1_table_reveal_spec.md`)

---

## What shipped

GFM pipe-tables in markdown source render as a real visual grid:
- Bold header row with subtle background tint.
- Thin horizontal separator between header and body.
- Vertical column dividers at column boundaries.
- Prominent 1.25pt / labelColor @ 60% outer borders on all four sides.
- Wrapped cell content within column width (max 320pt; min 60pt).
- Per-column alignment honored (leading / center / trailing from GFM `:---:` markers — currently applied only when the cell content is narrower than the column; wrapped text flows left).
- **Source stays in storage.** `document.source` is never modified — the grid is a rendering overlay via TextKit 2's custom-fragment substitution, not an edit.

---

## Approach — TextKit 2 custom layout fragments

We landed on **Approach D2** from the revised spec: `NSTextLayoutManager.delegate` returns a custom `NSTextLayoutFragment` subclass for paragraphs whose source range carries a `TableRowAttachment` attribute. Proof-of-concept spike ran in ~20 min and confirmed:
- The delegate is called per text element with the source's attributes available via `NSTextParagraph.attributedString`.
- Custom fragments replace default rendering for their element without modifying storage.
- `layoutFragmentFrame` governs flow-layout height; `renderingSurfaceBounds` governs draw bounds.

The spike's throwaway red-rect fragment became the production `TableRowFragment`.

---

## Module layout

```
Sources/Editor/Renderer/Tables/
├── TableAttributeKeys.swift          Attribute key the marker lives under.
├── TableLayout.swift                 Shared layout data (column widths,
│                                     alignments, pre-rendered cell attributed
│                                     strings, computed row heights) +
│                                     TableRowAttachment (per-row payload).
├── TableRowFragment.swift            NSTextLayoutFragment subclass — draws
│                                     cells, column dividers, outer borders,
│                                     header background, and the horizontal
│                                     head/body separator.
└── TableLayoutManagerDelegate.swift  Layout-manager delegate that swaps in
                                      TableRowFragment when the attachment
                                      attribute is present.
```

Plus small integrations:
- `Sources/Editor/Renderer/MarkdownRenderer.swift` — new `visitTable(_:)` method that precomputes the layout and tags row source ranges.
- `Sources/Editor/EditorContainer.swift` — installs the layout delegate on the text view's `NSTextLayoutManager` and retains it via the Coordinator.
- `Sources/Editor/Renderer/SourceLocationConverter.swift` — revisited to correctly convert UTF-8 byte columns to UTF-16 offsets (see Finding #3).

No new `.layoutManager` references (`grep -r '\.layoutManager' Sources/` only shows documentation comments forbidding it + existing `textLayoutManager` / `NSTextLayoutManager` API usage).

---

## Findings

**#1 — NSTextLayoutManager delegate substitution works cleanly on macOS 14+.** No `clipsToBounds`-class gotchas this time. The custom fragment replaces default text rendering without having to hide the underlying text via attributes. Source is present in storage; only the fragment's draw is visible. Spike-proven before implementation.

**#2 — Table.Head is the header row itself, not a wrapper around a Row.** First attempt used `table.head.children.compactMap { $0 as? Table.Row }` and got an empty list — the header was never tagged, and its source leaked through. Correct model: `table.head` *is* a `TableCellContainer` whose children are `Table.Cell`. `table.body.children` is the list of `Table.Row` (body rows). Updated to treat head as row-with-cells in layout terms.

**#3 — swift-markdown SourceLocation columns are UTF-8 bytes, not UTF-16 code units.** `SourceLocationConverter`'s doc comment from D2 warned about this and deferred the fix "when we hit a real problem." We hit it: every ✅ emoji (3 UTF-8 bytes, 1 UTF-16 code unit) before a cell boundary pushed that cell's NSRange 2 offsets past its logical end. D5 exhibited it starkly — the Deliverable cell grabbed the pipe + `✅` from the Status cell, and Status started at "omplete" (the "C" got consumed). Fix: converter now walks grapheme clusters accumulating `Character.utf8.count` bytes while tracking the corresponding UTF-16 offset. One-file change; benefits all D1+ renderers (Heading, Strong, Emphasis, InlineCode, Link, CodeBlock) by making their source ranges correct for multibyte content.

**#4 — swift-markdown Table.Row source ranges overshoot the logical line.** Raw `sourceNSRange(row)` ranges include a trailing newline plus a few chars of the next row's prefix — causing the attachment attribute to leak into the adjacent paragraph (visible as `## Candidates` inheriting the attachment during debug). Fix: `clampedLineRange(startingNear:within:)` walks to the first newline from the row's reported start and returns the clean single-line range. Applied to head, separator, and every body row.

**#5 — Cell content extraction needed first-line-only trimming.** `TableCell.range` can extend past the cell (into trailing pipe + newline + next row's first cell). First-pass implementation rendered D2 col 2 as "Complete — 2026-04-22 \\n| D4". Fix: take the first line of the extracted substring before trimming `| \t`. Independent of Finding #3 — both defects fixed.

**#6 — Process note: spike before building paid off.** Phase 1 spike took ~20 min and validated Approach D2 before any production code. Without it we would have guessed on NSTextAttachmentViewProvider's U+FFFC requirement (and learned mid-build that it modifies storage). Two spike guidelines worth keeping: (a) bounded time box, (b) test the hardest technical question first — everything else is implementation detail.

---

## Default cell renderer

V1 default renderer: plain-text cell content from source substring (trimmed of pipes and whitespace), rendered in body or bold font. Inline markdown inside cells (bold / italic / inline code / link) is NOT rendered with its styling in this phase — the cell shows the source characters verbatim.

The `CellRenderer` protocol anchor from the spec is not yet in place; the current layout file hardcodes the default behavior. Extensible cell rendering (checkboxes, status chips, inline-markdown inside cells) is a follow-on deliverable.

---

## Deferrals / known gaps

| Gap | Disposition |
|---|---|
| **Reveal on caret-in-table** — cursor can enter the table's source range but the grid fragment hides the source, so the user can't see what they're typing | **D8.1** (spec + plan + prompt drafted 2026-04-23 evening) |
| Inline markdown formatting inside cells (bold/italic/code/link) | Future deliverable — requires extending the cell renderer to parse cell content through the MarkdownRenderer AST |
| `CellRenderer` protocol (pluggable cell renderers per §4 of the spec) | Future deliverable — current code hardcodes the default; protocol abstraction is a refactor, not a feature |
| Wrapped cells with right/center alignment flow left (alignment only applied to unwrapped lines) | Polish follow-up |

---

## Verification

- Build green, no new `.layoutManager` references.
- Dogfood: `./scripts/md-editor docs/roadmap_ref.md` — all tables render as grids.
  - Header row with subtle tint + bold.
  - Separator line between header and body.
  - Vertical column dividers throughout.
  - Horizontal row dividers between rows.
  - 1.25pt labelColor @ 60% outer border, all four sides.
  - ✅ emojis render correctly in Status column across all rows (Finding #3).
  - D5's Status cell shows `✅ Complete — 2026-04-22` (no more `omplete`).
- Clicking into a cell does NOT yet reveal source — D8.1 scope.
- Scroll-to-line (D9), line numbers (D10), CLI view control (D11) all continue to work — no regression.

---

## Harmoniq

D8 was not on the Harmoniq project #53 task tree as a backlog entry — it was a D-level deliverable from the start. The "GFM table rendering" roadmap row is complete; D8.1 (reveal) will be a separate entry in the project log when the triad lands.
