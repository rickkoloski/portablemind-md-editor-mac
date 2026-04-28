# D24 Prompt — Responsive table column layout

You are working on `~/src/apps/md-editor-mac` on branch `feature/d24-responsive-table-columns`. Your job is to replace the existing 320pt-cap heuristic on markdown table column widths with a content-aware proportional layout that mirrors VS Code preview / browser `table-layout: auto` semantics — narrow columns hug their content, long-text columns share remaining viewport space proportionally, over-long unbreakable tokens ellipsize rather than push the table past the viewport.

This resolves backlog item **i02** (Markdown table column widths capped at 320pt regardless of viewport). The fix lifts every markdown table in the editor — spec docs, decision logs, comparison tables, all dogfooded daily.

---

## Read first (in this order)

1. `docs/current_work/specs/d24_responsive_table_columns_spec.md` — the contract. Decision log Q1-Q8 captures all eight scope answers (CD-approved 2026-04-28). **Q8 explicitly revises Q2** — read both; Q8 is the live behavior.
2. `docs/current_work/planning/d24_responsive_table_columns_plan.md` — six phases with DOD per phase + harness action additions. Phase 1 is a spike that gates Q8.
3. `docs/issues_backlog.md` — i02 is the entry this deliverable resolves; phase 6 marks it Fixed.
4. `docs/chronicle_by_concept/05_tables/_index.md` — the current TK1 table implementation (D17 era). The implementation surface is `Sources/Editor/Renderer/Tables/`.
5. `docs/chronicle_by_concept/04_tables_tk2_retired/_index.md` — **historical only.** Read only if a question arises about why we don't reach for TK2 fragment math; this code is retired.
6. `docs/engineering-standards_ref.md` — §3.1 (branching: `feature/d##-*`), §3 (D17 onwards: `LiveRenderTextView` uses `layoutManager`, NOT `textLayoutManager` — runtime trip-wire asserts).
7. Memory pointers (`~/.claude/projects/-Users-richardkoloski-src/memory/`):
   - `feedback_no_shortcuts_pre_users.md` — pre-user products build the hard thing right.
   - `md_editor_dogfood_workflow.md` — `**Question:**` / `**Decision:**` / `**Bug:**` / `**Assumption:**` markers (own line, greppable).
   - `feedback_focus_stealing.md` — ask before app launches, modals, anything that grabs focus.

---

## Reference behavior (mirror, don't import)

VS Code preview's table layout is the visible target. Two reference screenshots from the spec authoring session live conceptually as:
- Wider window: short-token columns lock at natural width; long-text Description column flexes to fill remaining viewport; some text wraps but only where unavoidable.
- Narrower window: short-token columns still lock at natural width; long-text columns wrap proportionally to their natural-width ratios.

Browser-side: `table-layout: auto` with text content is the same algorithm.

The spec's Algorithm section formalizes this in pseudocode (Pass 1 measure, Pass 2 distribute, Pass 3 apply). Implement that pseudocode directly — don't reinvent or improve it without surfacing a `**Question:**`.

---

## Where to work

Production code lives in `Sources/Editor/Renderer/Tables/`. Existing files (D17 era):
- `TK1TableBuilder.swift` (or similarly named — locate via `grep -rn 'columnCap'`) is where the 320pt cap currently lives.

New files to create (per phase):
- Phase 1 (spike): `spikes/d24_table_columns/SpikeApp.swift` + `README.md`. Discardable.
- Phase 2: `Sources/Editor/Renderer/Tables/TableNaturalWidthCache.swift`. Cache infrastructure.
- Phase 3: `Sources/Editor/Renderer/Tables/TableColumnDistribution.swift`. Pure-function distribution. Plus `UITests/TableColumnDistributionTests.swift` (XCTest).
- Phase 6: standard SDLC deliverable closeout files.

Harness extensions (TEST-HARNESS, `#if DEBUG`):
- `Sources/Debug/HarnessCommandPoller.swift` — new actions per phase (see plan §0.1).

---

## Phase-by-phase guidance

### Phase 1 — Spike

**Don't proceed past phase 1 without a recommendation.** If the spike comes back YELLOW or RED, stop and surface a `**Question:**` to CD with the observed behavior + proposed fallback.

The spike is intentionally minimal: a NSWindow + NSTextView containing one hand-built NSTextTable with three cells (normal text, over-long URL only, mixed). Apply `byTruncatingTail` paragraph style. Resize the window. Observe.

GREEN means all four claimed behaviors hold (spec §Algorithm Pass 3 + §Decision Q8). YELLOW means most hold but with a documented gotcha. RED means falling back to a custom NSLayoutManager hook (estimated +1 phase).

### Phase 2 — Measurement + cache

`natural_width(col)` is a CoreText measurement: shape each cell's longest single line, take the max across cells in the column. Don't double-count: cap each cell's contribution at `viewport_width` per Q8 before computing the column's max.

Cache key: `(table_anchor_id, content_hash_of_cells_per_column)`. The anchor must survive storage edits before/after the table — use a stable identifier from the parsed AST or a paragraph-style attribute, not an `NSRange`.

The harness action `dump_table_natural_widths` is your verification surface. After phase 2, opening any doc with tables and dumping should show sensible per-column widths even though the user's view hasn't changed yet (cap still in place).

### Phase 3 — Distribution

Pure function. No mutable state. The signature in the plan is the contract.

The lock-in pass converges in 1-2 iterations for typical doc shapes. Implement as a loop with an exit condition; don't unroll prematurely.

XCTest coverage is the verification surface — no harness needed for pure-function math. The fixtures listed in plan §Phase 3 exercise every spec edge case. **Do not skip the floor-wins case** (viewport < 60pt × n) — it's degenerate but it must not crash or return negative widths.

### Phase 4 — Apply

This is the visible milestone. The user sees the responsive layout for the first time after phase 4 lands.

Replace the 320pt cap. Read viewport width from `NSTextContainer.containerSize.width` — see plan risk 4 if this turns out to be wrong. Set per-cell paragraph style `lineBreakMode = .byTruncatingTail` on every cell.

The Decision-log table in `chronicle_by_concept/06_persistence_and_connectors/specs/d19_pm_save_back_spec.md` is the canonical visual smoke test — it's a 4-column table with one long-text column that's been demonstrating the i02 problem for weeks. Open it after phase 4 and confirm: "Decision" column is now wide enough that text doesn't wrap aggressively when the window is wide.

### Phase 5 — Resize debounce

100ms tail on `NSWindow.didResizeNotification`. Cancel and reschedule on every notification; fire once when the storm subsides. Don't use a Timer at low-millisecond intervals — use `Task.sleep` + `Task.cancel` or a `DispatchSourceTimer`.

The reflow path is cheap because Pass 1 (measurement) is cached. Only Pass 2 + Pass 3 run on resize. Targeting < 5ms per table.

### Phase 6 — Close out

Manual test plan covers every scenario from spec §Acceptance criteria 5. Each scenario gets a harness recipe block (matching D19's manual test plan §C cross-cutting harness recipe pattern).

Update i02 in `docs/issues_backlog.md`: `Status: Fixed (D24, 2026-04-28)`.

Update `docs/roadmap_ref.md`: D24 row → ✅ Complete; new change-log entry mentioning the i02 resolution.

---

## Conventions

- **Branch per deliverable** (`feature/d24-responsive-table-columns`). Each phase ends in a commit. Do not commit deliverable work directly to `main` — see CLAUDE.md SDLC compliance.
- **Harness-first verification** (per D18 plan §0.1, exercised in D19). Drive scenarios via `/tmp/mdeditor-command.json`; assert on emitted result files. XCUITest is one launch-smoke per area.
- **Manual test plan is a first-class deliverable artifact** — graduates to harness-driven assertion but the manual plan stays as the human-runnable mirror.
- **Markdown dogfood markers:** `**Question:**` / `**Decision:**` / `**Bug:**` / `**Assumption:**`, own line, greppable. Use them when something needs CD's attention or when an in-flight assumption needs to be made explicit.
- **Decision log table convention:** Date | Decision | Decided by; lives at end of working docs.
- **Surface review-ready docs** via `~/src/apps/md-editor-mac/scripts/md-editor file:line`.
- **Ask before any operation that grabs input focus** (per `feedback_focus_stealing.md`). MdEditor relaunch grabs focus; XCUITest grabs focus; modal dialogs grab focus.

---

## Done means

1. All six phases complete; one commit per phase on `feature/d24-responsive-table-columns`.
2. Manual test plan walked end-to-end with results recorded.
3. COMPLETE doc references spec, plan, prompt, manual test plan, and the i02 fix.
4. `xcodebuild test` GREEN (D18 i03 fix carried forward + new D24 unit tests).
5. `docs/issues_backlog.md` i02 → `Fixed (D24, 2026-04-28)`.
6. `docs/roadmap_ref.md` reflects D24 ✅ + change-log entry.
7. Branch merged to `main` and pushed; remote feature branch deleted (per recent CD-approved cleanup pattern from D19/D22/i04).
