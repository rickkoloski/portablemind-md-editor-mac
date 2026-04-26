# D17 Plan — TextKit 1 Migration

**Spec:** `docs/current_work/specs/d17_textkit1_migration_spec.md`
**Reference:** `spikes/d16_textkit1_tables/` (proven shape)
**Created:** 2026-04-26

---

## 0. Approach

Seven phases, each independently verifiable. Phases 1–2 establish the new foundation; phases 3–5 retire the old; phase 6 makes deferred decisions on D8.1/D12/D13 affordances; phase 7 closes the loop with a regression sweep + COMPLETE doc + manual test plan.

Each phase ends in a commit and a one-line entry in `STATUS.md` at the project root (or in the WIP migration folder) so we can resume after interruption without re-reading the diff.

Stop and surface a `**Question:**` to CD if any phase reveals a scope change. Don't paper over with workarounds — that's how we got into the TK2 corner in the first place.

---

## Phase 1 — Flip the text view to explicit TK1 init

Goal: every doc in the editor renders on TK1 from this commit forward. Tables WILL render incorrectly during this phase (still emitting TK2-shaped attributes); that's expected — phase 2 fixes them.

Files touched:
- `Sources/Editor/EditorContainer.swift` — `makeNSView` constructs `NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView` explicitly. Drop any TK2 init paths.
- `Sources/Editor/LiveRenderTextView.swift` — adopt the explicit-init constructor; remove any `textLayoutManager` usage that creeps in.

Do NOT yet:
- Touch the markdown renderer's table emission.
- Delete TableRowFragment.swift / TableLayoutManagerDelegate.swift (still referenced by current renderer; phase 3 deletes them).
- Remove scroll suppression / ensureLayout (still cosmetic; phase 5 cleans up).

DOD:
- App builds.
- Open a doc with NO tables. Renders correctly.
- Runtime assert (`#if DEBUG`): `textView.textLayoutManager == nil` after construction.
- Manual test plan §A1 (excluding tables) GREEN.
- Tables render visibly broken (expected). Note in commit message.

Commit: "D17 phase 1 — text view on explicit TK1 init; tables temporarily broken pending phase 2".

---

## Phase 2 — Emit NSTextTable attributes from the renderer

Goal: tables render correctly as native TK1 grids.

Files touched:
- `Sources/Editor/Renderer/Tables/TableLayout.swift` — augment / replace with code that builds a `NSTextTable` instance and per-cell `NSTextTableBlock` with the same column-width logic. The class likely shrinks: most of the layout math (rowHeight, columnLeadingX, drawCells) is now TK1's responsibility. What remains is a builder that produces the per-cell `NSAttributedString` chunks with correct paragraph styles.
- `Sources/Editor/Renderer/<wherever the markdown→attributed-string walk lives>` — at the table node in the markdown AST, emit a sequence of cell paragraphs (each terminated by `\n`) with `paragraphStyle.textBlocks = [theBlockForThisCell]`.

Reference: `spikes/d16_textkit1_tables/Sources/D16Spike/SpikeDoc.swift` shows the exact shape.

Subtleties:
- Header cells get `boldSystemFont`; body cells get `systemFont`. Match D8 visual baseline.
- Per-cell padding: D8 used a 6/10 inset; TK1 expresses this via `block.setWidth(_, type: .absoluteValueType, for: .padding)`. Match.
- Per-cell border: `block.setBorderColor(.separatorColor)`, `block.setWidth(1, ...)`.
- Column content width: set explicitly via `block.setContentWidth(_, type: .absoluteValueType)`. Pick the same per-column max-content width D8 picked.
- Source-range tracking: the renderer's existing source-range tracking still applies; each cell's paragraph corresponds to a source range in the markdown input, and the editor needs that range so cell-text edits can be re-serialized.

DOD:
- Open `docs/roadmap_ref.md`. Tables render as a grid with correct column widths and borders.
- Wrapped cells (long descriptions) wrap inside their column, stacking visual lines.
- Open d09 (multi-table). All tables render. Scroll up/down: no blank gaps, no stale fragments.
- Click a cell — caret lands inside cell text using stock NSTextView behavior (no overlay yet — overlays still mount because phase 4 hasn't retired them; this is OK temporarily but click-in-cell should work either way).

Commit: "D17 phase 2 — markdown renderer emits NSTextTable attributes; tables render natively in TK1".

---

## Phase 3 — Retire TK2 fragment code

Goal: delete TK2-only files. Codebase no longer knows what an `NSTextLayoutFragment` subclass is.

Files removed:
- `Sources/Editor/Renderer/Tables/TableRowFragment.swift`
- `Sources/Editor/Renderer/Tables/TableLayoutManagerDelegate.swift`
- `Sources/Editor/Renderer/Tables/CellSelectionDataSource.swift` if present

Files updated:
- `Sources/Editor/EditorContainer.swift` — drop the `let layoutDelegate = TableLayoutManagerDelegate()` wiring; remove `.delegate = layoutDelegate` line.
- `Sources/Editor/Renderer/Tables/TableAttributeKeys.swift` — `rowAttachmentKey` may still be used to track cell ranges for editing; keep if useful for D17, otherwise remove. Verify no other code references `TableRowAttachment`.
- `Sources/Editor/Renderer/Tables/TableRowAttachment.swift` — same eval; this was metadata for the TK2 fragment, may not be needed if cell ranges are tracked another way.

DOD:
- `grep -rn 'NSTextLayoutFragment\|NSTextLayoutManager\|TableRowFragment\|TableLayoutManagerDelegate' Sources/` returns zero hits.
- App builds and runs.
- Tables still render (phase 2 work intact).

Commit: "D17 phase 3 — retire TK2 custom-fragment code".

---

## Phase 4 — Retire D13 cell overlay machinery

Goal: TK1 supports in-place cell editing. The overlay was a workaround for D12's wrapped-cell limitation in TK2. Delete it.

Files removed:
- `Sources/Editor/Renderer/Tables/CellEditOverlay.swift`
- `Sources/Editor/Renderer/Tables/CellEditController.swift`
- `Sources/Editor/Renderer/Tables/CellEditModalController.swift` (defer/keep is § 6 in spec; default DROP)

Files updated:
- `Sources/Editor/LiveRenderTextView.swift` — remove `cellEditController` and `cellEditModalController` weak properties and their wiring.
- `Sources/Editor/LiveRenderTextView.swift` — `mouseDown` no longer mounts an overlay; default NSTextView click handling places caret in cell text. The override may shrink dramatically — possibly to nothing beyond what the cell-aware-nav `keyDown` needs (and that lives in phase 6's revisit).
- `Sources/Editor/LiveRenderTextView.swift` — `menu(for:)` override that adds "Edit Cell in Popout…" — remove if modal popout is dropped.
- `Sources/Editor/EditorContainer.swift` — drop `editController` and `modalController` instantiation, drop registration on the harness sink.
- `Sources/Debug/HarnessCommandPoller.swift` — drop overlay-/modal-specific actions: `show_overlay_at_table_cell`, `type_in_overlay`, `commit_overlay`, `cancel_overlay`, `open_modal_at_table_cell`, `set_modal_text`, `commit_modal`, `cancel_modal`. Drop the `cellEditController` / `cellEditModalController` weak references.

DOD:
- App builds.
- Click a cell. Caret lands in cell text. Type — characters appear in cell. No overlay.
- Tab from cell to cell does NOT yet work (phase 6 reinstates it for TK1).
- Manual test plan §B1, §B2 GREEN (basic click + type).

Commit: "D17 phase 4 — retire D13 cell overlay; in-place TK1 editing replaces it".

---

## Phase 5 — Retire scroll-suppression and ensureLayout workarounds

Goal: the TK2-only scroll-jump fixes go away.

Files updated:
- `Sources/Editor/LiveRenderTextView.swift` — remove `scrollSuppressionDepth`, `scrollRangeToVisible(_:)` override, the `isNavigationKey` helper, the keyDown wrap that increments/decrements suppression, and `recordClickForDebugProbe`'s `ensureLayout` call (HUD readout still works against `glyphIndex(for:)`).
- `Sources/Editor/LiveRenderTextView.swift` — remove `mouseDown`'s leading `tlm.ensureLayout(for: tcm.documentRange)` block.
- `Sources/Editor/EditorContainer.swift` — remove `renderCurrentText`'s post-render `tlm.ensureLayout(...)`.
- `Sources/Editor/EditorContainer.swift` — remove the scrollY save+restore block in `renderCurrentText` (D15 origin).
- `Sources/Editor/EditorContainer.swift` — keep the scroll-bounds observer that feeds the debug HUD (different code, shorter — just `DebugProbe.shared.recordScroll(...)`).

DOD:
- App builds.
- Type at the bottom of the visible area — viewport behaves normally (NSTextView's natural auto-scroll-to-keep-caret-visible IS what we want now; the suppression we built was specifically to fight TK2's overshoot).
- Manual test plan §C (scroll + click interleave) GREEN.

Commit: "D17 phase 5 — retire TK2-only scroll workarounds; rely on stock TK1 behavior".

---

## Phase 6 — Reinstate cell-aware affordances on TK1

Goal: per the spec's open questions, restore cell-Tab navigation on TK1. Defer / drop the rest unless CD has flagged keep.

Files updated:
- `Sources/Editor/LiveRenderTextView.swift` — `keyDown` re-implements Tab/Shift+Tab between cells. Cell ranges are knowable from the attributed string's paragraph-style.textBlocks: walk the storage to find the next paragraph whose textBlocks list contains a block from the same NSTextTable. Move caret to its start.
- `Sources/Editor/LiveRenderTextView.swift` — left/right arrow at cell boundary: optional, decide during phase 6 whether the natural NSTextView behavior is acceptable. Default: leave as natural (arrow keys move into the next paragraph naturally; that's effectively the next cell).

What we explicitly DO NOT add back in this phase:
- Active-cell border affordance (D13 §3.7) — defer per spec § 5 ¶3.
- Modal popout — defer per spec § 5 ¶2.
- Source-reveal mode (D8.1) — defer per spec § 5 ¶1, default drop.

DOD:
- Click a cell, press Tab. Caret moves to next cell. Press Shift+Tab. Caret moves back.
- Tab past last cell of a row → first cell of next row (or end-of-table if last row).
- Manual test plan §F: HUD readout shows "tbl(r=N,c=M)" for cells, "para" for non-table paragraphs.

Commit: "D17 phase 6 — TK1 cell-Tab navigation; deferred D8.1/D13 affordances flagged".

---

## Phase 7 — Regression sweep, foundation-doc updates, COMPLETE

Goal: verify nothing in the wider codebase still depends on TK2-shaped types; update foundation docs; close the loop.

Activities:
- `grep -r 'NSTextLayoutFragment\|NSTextLayoutManager\|TableRowAttachment\|TableRowFragment\|TableLayoutManagerDelegate\|CellEditOverlay\|CellEditController\|CellEditModalController' Sources/` — must be zero hits.
- Update `docs/stack-alternatives.md` per spec § 4 DOD #6.
- Update `docs/engineering-standards_ref.md` § 2.2 per spec § 4 DOD #7.
- Update `docs/roadmap_ref.md`: mark D17 Complete; update D8/D8.1/D12/D13/D15/D15.1 entries to indicate they were superseded by D17 (with brief note "TK2-era; superseded by TK1 migration").
- Re-run `tests/harness/test_d15_1_lazy_layout.sh` against the new build. If assertions still apply (cell-range invariants), GREEN. If TK2-shaped harness actions are now removed, retire that test or rewrite for TK1 — don't leave broken tests in-tree.
- Write `docs/current_work/stepwise_results/d17_textkit1_migration_COMPLETE.md` per project conventions.
- Write `docs/current_work/testing/d17_textkit1_migration_manual_test_plan.md` covering spec § 6.
- Tag `v0.5-tk1` after CD verifies manual plan GREEN.

DOD:
- All foundation docs updated.
- COMPLETE doc + manual test plan in place.
- Tag pushed (after CD ack).
- Spike at `spikes/d16_textkit1_tables/` retained in-tree as reference, NOT deleted.

Commit: "D17 phase 7 — regression sweep + foundation docs + COMPLETE".

---

## Out-of-band concerns

### Keep an eye on

- Markdown serializer (attributed string → markdown source on save) when a cell is edited. D14's save path writes `document.source` (the raw markdown string), not a re-serialization of the attributed string — verify that's still the path post-migration. If we ever switch to "save by re-serializing", the table-attribute round-trip becomes the surface.
- File watcher: external edits trigger `document.source = current` and `renderCurrentText`. Verify the new render path handles re-rendering after an external edit cleanly.
- The spike's `D16Spike.app` directory is not committed (it's a build artifact). Add `spikes/d16_textkit1_tables/D16Spike.app/` and `spikes/d16_textkit1_tables/.build/` to `.gitignore` if they aren't already.

### What to defer to a follow-up deliverable (D18+)

- Active-cell border (Numbers/Excel-style affordance).
- Modal popout for long-form cell editing (if dogfooding shows demand).
- Performance pass (lazy-renderer cost, large-doc layout speed).
- Column resize / column sort (out of scope for migration; new feature work).

---

## Risk register

| Risk | Phase | Mitigation |
|---|---|---|
| Phase 1's TK1 init breaks something subtle in non-table content (e.g., bold/italic rendering) | 1 | Phase 1 DOD includes a non-table-doc smoke. If broken, surface immediately. |
| Renderer's TK1 attributed-string output has subtle width mis-calculations vs old D8 grid widths | 2 | Snapshot before/after. Visual diff is acceptable; numeric column widths can be tuned. |
| `enumerateLineFragments` API differs from `enumerateTextLayoutFragments` enough that the line-number ruler regresses | 1 (ruler is touched here implicitly when text view is rebuilt) | Test §E1 immediately after phase 1. |
| Editing a cell + saving produces incorrect markdown | 4 (when overlay is removed) | Test §D1: edit cell, ⌘S, verify file content. Save path writes from `document.source`; cell edit must write back into source via the same mechanism D14 used. |
| External edit watcher (NSFilePresenter) behaves differently with TK1 storage | continuous | Test §G1 at end of each phase. |
| Markdown source has cell content that includes characters that markdown table syntax escapes (pipes, backslashes); TK1 cell paragraphs render escaped chars as text | 2 | D13's commit() pipe-escaped on write; the inverse un-escape on render. The renderer for phase 2 needs the un-escape step too. Mirror D13. |
| Some D-doc content is a deeply-nested table that wraps within a wrapping cell | 6 | Visual verification only; in scope for D18+ if it surfaces. |