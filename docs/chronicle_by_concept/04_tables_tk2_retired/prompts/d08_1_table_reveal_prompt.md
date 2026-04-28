# D8.1: Table Reveal on Caret-In-Range — CC Prompt

**Spec:** `docs/current_work/specs/d08_1_table_reveal_spec.md`
**Plan:** `docs/current_work/planning/d08_1_table_reveal_plan.md`

---

## Context

D8 shipped the table grid rendering via TextKit 2 custom `NSTextLayoutFragment` substitution. Source stays in storage but is hidden under the grid. Users can't edit a table because they can't see what they type.

D8.1 adds reveal: when the caret enters a table's source range, that table flips to default text rendering (source visible). When the caret leaves, it flips back to grid. Whole-table reveal (not per-row).

**Read before starting:**
- `docs/current_work/specs/d08_1_table_reveal_spec.md`
- `docs/current_work/planning/d08_1_table_reveal_plan.md`
- `Sources/Editor/Renderer/Tables/TableLayoutManagerDelegate.swift`
- `Sources/Editor/Renderer/Tables/TableLayout.swift`
- `Sources/Editor/EditorContainer.swift` — Coordinator.textViewDidChangeSelection
- `Sources/Editor/Renderer/MarkdownRenderer.swift` — visitTable

---

## Task

Implement reveal-on-caret-in-table per the spec + plan.

### Specific requirements

1. `TableLayout` gains `tableRange: NSRange`. Populated from `visitTable` in MarkdownRenderer.
2. `TableLayoutManagerDelegate` gains `revealedTables: Set<ObjectIdentifier>`. Delegate method returns default fragment for revealed layouts, custom fragment otherwise.
3. Coordinator tracks `revealedTableLayoutID` and updates it on selection change.
4. On reveal state change, invalidate the affected table's `tableRange` via `NSTextLayoutManager.invalidateLayout(for:)` converted to `NSTextRange`.
5. No `.layoutManager` references.
6. Per-table reveal — entering table A reveals A only; moving to table B reveals B and hides A.

---

## Constraints

- **Whole-table reveal.** Per-row reveal is explicitly out of scope.
- **No storage modification.** Source buffer never changes on reveal — only attribute on fragments + invalidation.
- **Delimiter reveal (CursorLineTracker) must not regress.** Delimiter handling and table reveal are independent.
- **No new keyboard shortcuts.** Caret movement drives reveal.
- **Dogfood before declaring done.** Open `docs/roadmap_ref.md`, click inside a cell, type, arrow out. Verify grid re-renders with the edit.

---

## Success Criteria

- [ ] Click inside any cell of any table → that table reveals (pipes + source visible).
- [ ] Arrow / click out of the table → grid re-renders.
- [ ] Typing inside a revealed table persists the edit.
- [ ] Two tables reveal independently.
- [ ] No `.layoutManager` added (grep confirms).
- [ ] D8, D9, D10, D11 all still work.

---

## On Completion

Create `docs/current_work/stepwise_results/d08_1_table_reveal_COMPLETE.md` documenting:
- What was implemented
- Files created/modified
- Findings (expected: at least one TextKit 2 invalidation timing gotcha)
- Any deviations from spec + plan

Update `docs/roadmap_ref.md` to mark D8.1 complete.

Commit + push.
