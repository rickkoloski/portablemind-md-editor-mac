# D16 Prompt — TextKit 1 Tables Spike

You are working on `~/src/apps/md-editor-mac`. Your job is to
build a TextKit 1 spike that validates whether native
`NSTextTable` / `NSTextTableBlock` resolves the table-rendering
+ click + scroll bugs we couldn't tame in TextKit 2 across D8 →
D15.1.

**Read first** (in this order):
1. `docs/current_work/specs/d16_textkit1_tables_spike_spec.md`
2. `docs/current_work/planning/d16_textkit1_tables_spike_plan.md`
3. `docs/current_work/stepwise_results/d15_1_scroll_jump_root_cause_COMPLETE.md`
   — the "Pivot to TextKit 1" section explains the architectural
   rationale.

The four scenarios that defeated us in TK2:
1. Open a doc whose table is below the initial viewport, scroll
   to it — does the table render correctly?
2. Click any cell — does the caret land inside cell text?
3. Type with the caret in a cell — does scroll position hold?
4. Click on visual line 2 of a wrapped cell — does the caret
   land at the correct char offset?

GREEN definition: all four pass without any of these workarounds:
- `NSTextLayoutFragment` subclass.
- Layout-manager delegate that re-implements positioning.
- Scroll suppression / scroll preservation hooks.
- `ensureLayout` calls in click handlers.

If we have to reach for any of those, we've moved frameworks
without solving the class of problem — that's RED, document why
and stop.

---

## Where to work

`spikes/d16_textkit1_tables/` — new directory. Mirror the layout
of `spikes/d13_overlay/`:
- `Package.swift` (Swift Package, not Xcodegen)
- `run.sh` (launcher)
- `Sources/D16Spike/main.swift` (entry)
- `Sources/D16Spike/...` (additional files as needed)
- `FINDINGS.md` (per-phase results)
- `STATUS.md` (final verdict)

**Do NOT modify anything in `Sources/` (production code) or
`MdEditor.xcodeproj/`.** The spike is standalone. The whole point
is to answer the architectural question without disturbing the
production code path until we've decided.

---

## How to work

Follow the plan's phases in order:
- Phase 1: project skeleton.
- Phase 2: render the table (Scenario 1).
- Phase 3: click-to-caret (Scenario 2).
- Phase 4: type-without-jump (Scenario 3).
- Phase 5: wrapped-cell click (Scenario 4).
- Phase 6: write FINDINGS.md + STATUS.md.

Stop at the first RED phase — that answers the question.

---

## What to deliver

1. The standalone spike app under `spikes/d16_textkit1_tables/`,
   buildable via `./run.sh`.
2. `FINDINGS.md` with a section per phase: scenario, observed
   behavior, status (GREEN / YELLOW / RED), notes, next
   questions.
3. `STATUS.md` with overall verdict and a recommendation:
   - "Proceed with migration" (all GREEN, or YELLOW only on
     items that don't break the canonical scenarios).
   - "Spike inconclusive — refine and re-run" (RED on something
     that might be fixable in the spike itself).
   - "Fall back to TK2 with [SuperSwiftMarkdownPrototype][1] as
     reference" (RED on something fundamental).

[1]: https://github.com/SuperSwiftMarkup/SuperSwiftMarkdownPrototype

---

## What NOT to do

- Don't ingest markdown. Hard-code an `NSAttributedString` with
  table attributes. The spike is about TK1's rendering + click
  + scroll behavior, not about parsing.
- Don't migrate any production code. The migration plan is a
  separate triad after the spike's verdict.
- Don't reach for the SuperSwiftMarkdownPrototype reference
  during the TK1 spike. CD's framing: "approach with healthy
  skepticism." It's a fallback if TK1 fails, not a parallel
  investigation. Stay focused on the TK1 question.
- Don't try to keep the TK2 production code working in parallel.
  The spike is isolated; running on the side has zero impact on
  what's currently shipped.
- Don't spend effort on D8.1 reveal mode, cell-tab nav, active-
  cell border, modal popout, or save/load. Out of scope per
  spec § 2.

---

## Calibration

The spike's job is to produce a clear verdict with evidence. A
GREEN that needs "but we'd also need..." caveats isn't GREEN;
it's YELLOW. A RED with "but maybe if we…" isn't RED yet; do the
maybe and re-evaluate. Be precise.

If you discover something that changes the migration cost
estimate (e.g., "TK1 handles tables but `NSLayoutManager` is
heavily deprecated and warnings are everywhere"), capture it in
FINDINGS.md. The cost-of-migration shape is decision input even
when the spike GREENs.

---

## When stuck

If you genuinely can't make a phase work and aren't sure whether
it's a TK1 limitation or a usage error, stop and add a `**Question:**`
marker to FINDINGS.md (per `~/src/shared/prompts/use-md-editor.md`
convention). Don't keep grinding — surface the question. Rick
will pick it up on the next touchpoint.

The spike is bounded: ≈1 day. If you cross that without a
verdict, write what you have to STATUS.md as "inconclusive" with
the specific question that needs unblocking.