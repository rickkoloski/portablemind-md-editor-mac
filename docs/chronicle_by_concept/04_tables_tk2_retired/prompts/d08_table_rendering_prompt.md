# D8: GFM Table Rendering — CC Prompt

**Spec:** `docs/current_work/specs/d08_table_rendering_spec.md`
**Plan:** `docs/current_work/planning/d08_table_rendering_plan.md`

---

## Context

md-editor-mac renders markdown with a visitor over swift-markdown's AST at `Sources/Editor/Renderer/MarkdownRenderer.swift`. D1-D7 handle Heading, Strong, Emphasis, InlineCode, Link, CodeBlock. GFM tables currently fall through as plain paragraph text — pipes visible, nothing aligned. Our dogfood corpus (`docs/`) leans on pipe-tables for roadmap matrices, stack decision tables, and dimension matrices, so this is a real gap once we're using the editor on our own SDLC artifacts.

D8 adds real table rendering using the same reveal-scope mechanic CodeBlock already uses: cursor outside → rendered grid; cursor inside → pipe-delimited source.

**Read before starting:**
- `docs/current_work/specs/d08_table_rendering_spec.md` (the full spec — approach, tradeoffs, open questions)
- `docs/current_work/planning/d08_table_rendering_plan.md` (the step-by-step plan)
- `docs/engineering-standards_ref.md` (every standard — especially §2.2 no `.layoutManager`)
- `Sources/Editor/Renderer/MarkdownRenderer.swift` (the renderer you'll be extending)
- `Sources/Editor/Renderer/CursorLineTracker.swift` (the reveal-scope consumer you'll be touching)
- `Sources/Support/Typography.swift` (where the new table typography constants land)

**Key Files:**
- `Sources/Editor/Renderer/MarkdownRenderer.swift` — dispatch extension point
- `Sources/Editor/Renderer/Tables/` — new sub-module you'll create
- `Sources/Editor/Renderer/CursorLineTracker.swift` — reveal-scope tracker, needs to handle the new table reveal kind
- `Sources/Support/Typography.swift` — table typography constants
- `MdEditorTests/TableRendererTests.swift` — new unit tests
- `UITests/TableRevealTests.swift` — new UITests

**Related Deliverables:** D1 (TextKit 2 hosting), D2 (renderer + RenderResult + RenderVisitor pattern)

---

## Task

Implement GFM table rendering per the D8 spec, following the D8 plan. Tables render as visual grids when the cursor is outside their range; as pipe-delimited source when the cursor is inside, via the existing reveal-scope mechanic.

### Specific Requirements

1. Add `case let table as Table: visitTable(table)` to `RenderVisitor.walk`. Delegate to `TableRenderer.render(_:into:)` in a new `Sources/Editor/Renderer/Tables/` sub-folder.
2. Create four new files under `Sources/Editor/Renderer/Tables/`: `TableRenderer.swift`, `TableMeasurement.swift`, `TableAttributes.swift`, `TableRevealScope.swift`. Each stays under ~150 lines or is split further.
3. Column widths measured per-column as the max of cell content widths (body-font plain-text width is acceptable approximation at D8; note in COMPLETE doc if inline-formatting widths become a problem).
4. Per-column alignment from `Table.columnAlignments` applied. All three alignment markers (`:---`, `:---:`, `---:`) honored; missing column alignments default to leading.
5. Header row (`TableHead`) uses `Typography.tableHeaderFont` (new constant: body size, bold). A visible horizontal separator sits between header and body.
6. Pipes and separator-row dashes are visually hidden when the cursor is outside the table. When the cursor enters the table range, reveal-scope flips to source view — pipes and dashes become visible.
7. Reveal scope covers the **whole table**, matching CodeBlock's whole-block pattern. Use a new attribute key `Typography.tableRevealScopeKey` — do not overload the existing `revealScopeKey`.
8. `CursorLineTracker` extended to handle the new reveal kind. Existing delimiter reveal behavior must not change (verify with a rerun of existing UITests before committing).
9. Spike the attribute-only pipe-hiding + tab-stop column alignment path for no more than 2 hours. If it doesn't converge, fall back to `NSTextAttachment`-backed per-row rendering (Approach B from spec §3.1). Document the decision as a numbered finding in the COMPLETE doc.
10. No new `.layoutManager` references. Confirm with `grep -r '\.layoutManager' Sources/` before finalizing.

### Files to Create/Modify

| File | Action |
|------|--------|
| `Sources/Editor/Renderer/MarkdownRenderer.swift` | Modify — add Table dispatch |
| `Sources/Editor/Renderer/Tables/TableRenderer.swift` | Create |
| `Sources/Editor/Renderer/Tables/TableMeasurement.swift` | Create |
| `Sources/Editor/Renderer/Tables/TableAttributes.swift` | Create |
| `Sources/Editor/Renderer/Tables/TableRevealScope.swift` | Create |
| `Sources/Editor/Renderer/CursorLineTracker.swift` | Modify — handle tableRevealScopeKey |
| `Sources/Support/Typography.swift` | Modify — add tableHeaderFont, tableHeaderSeparatorColor, tableCellInset, tableRevealScopeKey |
| `MdEditorTests/TableRendererTests.swift` | Create |
| `UITests/TableRevealTests.swift` | Create |
| `docs/fixtures/tables-alignment.md` | Create — fixture for alignment tests |
| `docs/fixtures/malformed-table.md` | Create — fixture for malformed-input regression test |
| `docs/current_work/stepwise_results/d08_table_rendering_COMPLETE.md` | Create on completion |
| `docs/roadmap_ref.md` | Modify — mark D8 complete |

---

## Constraints

- **Engineering standards §2.2 — no `.layoutManager` references.** TextKit 2 only (`NSTextContentManager` / `NSTextLayoutManager`). If any custom layout work needs pre-layout geometry, obtain it from TextKit 2 APIs.
- **Reveal-scope symmetry must be preserved.** Any change to `CursorLineTracker` that affects the delimiter reveal path is a red flag — revert and try a narrower change.
- **Don't walk Table children in the default visitor.** `visitTable` owns the entire sub-tree; after it's called, the default `for child in markup.children` branch must not also run on the Table's descendants. Prevents double-attribution.
- **Don't rewrite source.** Source pipes and dashes stay in the buffer verbatim. All styling is attribute-only (or NSTextAttachment-backed, which also doesn't modify the buffer).
- **No new keyboard shortcuts.** D8 is a rendering deliverable only.
- **No Insert-Table toolbar button.** Out of scope (spec §5).
- **Don't declare victory before dogfood run.** UITest green is not sufficient. Open `docs/roadmap_ref.md` and `docs/stack-alternatives.md` in the actual app and confirm the grids render correctly.

---

## Success Criteria

- [ ] Every GFM table in `docs/roadmap_ref.md`, `docs/stack-alternatives.md`, `docs/portablemind-positioning.md`, `docs/competitive-analysis.md` renders as a column-aligned grid with bold header row and visible header separator.
- [ ] Cursor enters any table → pipe-delimited source reveals across the whole table. Cursor leaves → grid re-renders.
- [ ] All three alignment markers render correctly (use `docs/fixtures/tables-alignment.md` fixture).
- [ ] Malformed pipe sequence renders as plain paragraph, no crash (use `docs/fixtures/malformed-table.md`).
- [ ] `TableRendererTests` and `TableRevealTests` pass.
- [ ] All prior D1-D6 tests still pass.
- [ ] `grep -r '\.layoutManager' Sources/` returns no new hits.
- [ ] COMPLETE doc records the Q1 outcome (attribute-only vs. attachment-backed) plus every finding surfaced along the way.

---

## On Completion

Create `docs/current_work/stepwise_results/d08_table_rendering_COMPLETE.md` documenting:
- What was implemented (module layout, rendering approach chosen — attribute-only vs. attachment-backed).
- Files created and modified (full list).
- Test results (unit + UITest + dogfood screenshots).
- Findings — numbered, with root cause + fix, same pattern as D6's COMPLETE doc.
- Any deviations from spec, with justification.
- Known polish items deferred (e.g., column-resize drag, structured-edit mode, Insert-Table toolbar button).

Update `docs/roadmap_ref.md` to mark D8 complete.

Commit with a clear message. Do NOT amend or force-push; create a new commit at the end.
