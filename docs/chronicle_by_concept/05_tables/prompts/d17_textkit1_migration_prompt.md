# D17 Prompt — Migrate Editor to TextKit 1

You are working on `~/src/apps/md-editor-mac`. Your job is to migrate the main editor view from TextKit 2 (`NSTextLayoutManager`) to TextKit 1 (`NSLayoutManager`), retiring the custom-fragment table system and the cell-edit overlay it required.

This is a **foundational migration**, not a feature addition. Code volume goes DOWN; the architecture gets simpler.

---

## Read first (in this order)

1. `docs/current_work/specs/d17_textkit1_migration_spec.md` — the contract.
2. `docs/current_work/planning/d17_textkit1_migration_plan.md` — the seven phases with DOD per phase.
3. `spikes/d16_textkit1_tables/STATUS.md` and `FINDINGS.md` — what the spike validated and the cost-of-migration breakdown.
4. `spikes/d16_textkit1_tables/Sources/D16Spike/SpikeDoc.swift` — the exact NSTextTable / NSTextTableBlock shape to port. Don't import code; mirror the pattern in `Sources/Editor/Renderer/...`.
5. `docs/current_work/stepwise_results/d15_1_scroll_jump_root_cause_COMPLETE.md` — context on why we're doing this.

---

## What changes

The summary: the editor stops using TextKit 2's custom-fragment system for tables. Tables become native `NSTextTable` / `NSTextTableBlock` content within an attributed string. The text view is constructed with explicit TK1 init (`NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView`).

A substantial slice of D8/D12/D13's code retires:
- `TableRowFragment.swift`, `TableLayoutManagerDelegate.swift` — TK2-only.
- `CellEditOverlay.swift`, `CellEditController.swift`, `CellEditModalController.swift` — workarounds for TK2's wrapped-cell limitation; TK1 supports in-place editing.
- `LiveRenderTextView.scrollSuppressionDepth` and the `scrollRangeToVisible` override — fought TK2's auto-scroll-on-edit.
- `LiveRenderTextView.mouseDown`'s leading `tlm.ensureLayout(for: tcm.documentRange)` and `EditorContainer.renderCurrentText`'s post-render `ensureLayout` — TK2-specific lazy-layout fixes.
- `EditorContainer.renderCurrentText`'s scrollY save+restore — D15-era placebo.

What survives unchanged: workspace shell, save/load, file watcher, command surface, line numbers, scroll-to-line, debug HUD, and the harness scaffolding (with table-shaped actions rewritten against TK1's APIs).

What gets re-evaluated per spec § 5: D8.1 source-reveal mode (default DROP), D13 modal popout (default DROP), active-cell border affordance (DEFER to D18+), cell-Tab nav (KEEP, port to TK1).

CD has not yet marked the open-question recommendations. **Default to my recommendations in spec § 5.** If you disagree with one, surface a `**Question:**` to CD before committing the phase that decides it.

---

## Where to work

Production code in `Sources/`. The xcodegen project gets re-generated as needed (`xcodegen generate` after adding/removing files).

Do NOT edit code in `spikes/d16_textkit1_tables/` — that's the reference spike, kept in-tree intentionally.

---

## How to work

Follow the phases in `d17_textkit1_migration_plan.md` in order. Phases are designed to be independently buildable and runnable so you can stop and verify between each.

Per phase:
1. Read the phase's "Files touched" + "DOD".
2. Make the change.
3. Build (`source scripts/env.sh && xcodebuild ...`).
4. Run the smoke for that phase's DOD (open the app, click around, type — phase 1's smoke is "non-table doc renders fine"; phase 2's is "tables render natively"; etc.).
5. Commit per the message in the plan.

If a phase's DOD doesn't go GREEN, don't paper over with workarounds. Stop and surface a `**Question:**` per `~/src/shared/prompts/use-md-editor.md`.

---

## Critical: do not mix TK1 and TK2

Per Apple at WWDC22, mixing TK1 and TK2 within an NSTextView is impossible: a text view has one layout manager. The migration is a clean switch. **Do not** keep a parallel TK2 path "for documents without tables." That's TextEdit's automatic compatibility-mode fallback, not a designed pattern. The spec § 2 explains why we're committing.

If during phase 1 you find any code that branches on `if let tlm = textView.textLayoutManager`, that's a vestigial TK2 path and should be removed (delete the branch, keep the TK1 code).

---

## Engineering standards update

`docs/engineering-standards_ref.md` § 2.2 currently says "never touch `NSTextView.layoutManager`" because the prohibition was about *accidentally* falling into TK1 from a TK2 codebase. Post-migration, that prohibition is inverted: we are deliberately on TK1. Reach for `layoutManager` directly when needed. The new prohibition (in phase 7's update): do not opt back into TK2 — no `NSTextView(usesTextLayoutManager: true)`, no `NSTextLayoutManager`-typed access — without raising a deliberate architecture decision.

Update this in phase 7. Don't leave it stale.

---

## Save / load and external edit watcher

Verify continuously across phases:
- `⌘S` saves changes to disk.
- External `echo > file.md` reflects in the open buffer.
- `⌘⇧S` saves to a new path.

These are independent of TextKit version, but they touch the storage path. If `document.source = current` semantics break post-migration, that's a phase-level RED.

---

## Manual test plan

Spec § 6 is the manual-test surface. After phase 7, you (or CC + CD together) walk through each section. Output goes in `docs/current_work/testing/d17_textkit1_migration_manual_test_plan.md` (template per project conventions).

The test plan is a deliverable. Don't skip it.

---

## What NOT to do

- Don't migrate non-table content rendering. Headings, lists, blockquotes, inline formatting all stay on whatever paragraph-style attributes they already use.
- Don't add new table features (resize, sort, etc.). Out of scope.
- Don't port code from `spikes/d16_textkit1_tables/`. Mirror the pattern; the spike is illustrative, not a library.
- Don't preemptively port to "modernized" TK1 alternatives that don't exist. Some TK1 APIs (e.g., `NSTextBlock.ValueType.absoluteValueType`) have older-style enum names. Use them as-is. Document any deprecation warnings; don't suppress wholesale.
- Don't introduce new third-party dependencies. The migration is API-level, not library-level.
- Don't skip phase 7. The foundation-doc updates (`stack-alternatives.md`, `engineering-standards_ref.md`, `roadmap_ref.md`) are migration-blocking; without them the next session's CC won't know we're on TK1.

---

## Calibration

The spec's DOD is binary per item. The plan's per-phase DOD is binary per phase. If you finish phase 4 and "tables click correctly but `cellEditOverlay` is still in the codebase," that phase isn't done — the deletion is the work, not a side effect.

Be explicit about anything you defer. If a deferred item has a follow-up deliverable, file it as `D18: ...` in the COMPLETE doc's "Deferrals" section. CD reads that section as the to-do for next-session.

---

## When stuck

Per `~/src/shared/prompts/use-md-editor.md` — add a `**Question:**` marker in the COMPLETE doc OR in your in-flight code change's commit message. Do not keep grinding past a real architectural question. CD's protocol from the D15.1 → D16 pivot: surface the question early, get the cheap answer, save the expensive grind.

---

## Schedule

This is a multi-day migration. CD is unlikely to be available continuously. Run autonomously per the phases; commit per phase; CD reads the latest commit + the current `STATUS.md` to catch up between sessions.

If you cross a full day on a single phase without GREEN, that's the signal to stop and surface a question rather than push harder.