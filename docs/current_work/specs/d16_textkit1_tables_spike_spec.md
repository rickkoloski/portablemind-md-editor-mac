# D16 Spec — TextKit 1 Tables Spike

**Type:** Spike (validate-or-rule-out architecture)
**Created:** 2026-04-26
**Outcome:** Decide whether to migrate the editor's table surface from
TextKit 2 (custom `NSTextLayoutFragment`) to TextKit 1 (native
`NSTextTable` / `NSTextTableBlock`).

---

## 1. Why this exists

D8 → D13 built table rendering and per-cell editing on TextKit 2's
custom-fragment system. D15.1 closed every harness-reproducible
post-scroll layout bug, but real-user dogfooding still surfaced
visual layout bugs — overlay placement after wheel scroll, missing
fragment renders mid-transition, line-number ruler artifacts. Each
fix targeted a specific symptom; the underlying class of bug
(lazy-layout vs custom-fragment-frame vs scroll viewport) keeps
recurring in different shapes.

CD direction (2026-04-26): "it's a poor choice to fight a
technology 99% of the time. We're fighting." Apple's own TextEdit
falls back to TextKit 1 when a table is inserted. That's a
non-trivial signal: the company that owns both APIs picks TK1 when
a table arrives.

This spike validates that signal at our scale before committing to
a migration.

---

## 2. Scope

**In scope** — the four scenarios that defeated D8–D15.1 in TK2:

1. **Static render** — open a doc whose table is below the initial
   viewport. Scroll into it. Does the table render correctly with
   no missing rows / wrong positions / partial layouts?
2. **Click-to-caret** — click any cell. Does the caret land in the
   cell's text content (not in a pipe character or whitespace)?
3. **Type-without-jump** — with the caret in a cell, type text.
   Does the scroll position hold (no auto-scroll-to-caret jumps,
   no layout-reflow shifts)?
4. **Wrapped-cell click** — for a cell whose content wraps to two
   visual lines, click on visual line 2. Does the caret land at
   the correct character offset within that wrapped line?

**Out of scope** — defer to the post-spike migration plan if the
spike GREENs:
- Source-fidelity round trip (markdown → TK1 attributed string →
  markdown)
- Source-reveal mode (D8.1 equivalent)
- Tab/arrow nav between cells (D12 equivalent)
- Inline formatting inside cells
- Multi-table documents (validate one table; assume composability)
- Save/load (D14 equivalent)
- File watcher / external edit
- Performance under large tables

The four scenarios above are the canonical bug surfaces. If TK1
handles them natively, the rest is engineering. If it doesn't, the
rest doesn't matter.

---

## 3. Definition of done

A `spikes/d16_textkit1_tables/` standalone Swift Package app that:

1. Hosts a single `NSTextView` configured with TK1
   (`NSLayoutManager` / `NSTextStorage` / `NSTextContainer`).
2. Loads a hard-coded markdown source string with one GFM-style
   table (≥ 4 columns, ≥ 10 body rows, with at least one row that
   wraps when rendered at the configured column width).
3. Programmatically converts the markdown table into an
   `NSAttributedString` with native TK1 table attributes
   (`NSTextTable`, `NSTextTableBlock` per cell, `NSParagraphStyle`
   with `textBlocks` set).
4. Below the table, includes ≥ 100 lines of plain text so the
   table sits below the initial viewport when the window is
   normal-sized (~1000pt tall).

The spike app then validates each of the four scenarios above
without writing custom layout/fragment code:

- **Scenario 1 (render)**: launch the app, scroll the text view to
  bring the table into view. Verify visually + via a status-line
  readout that the table draws as a grid with no missing rows.
- **Scenario 2 (click)**: click any cell. Verify the caret lands
  inside the cell text, not in a separator/pipe.
- **Scenario 3 (type)**: place caret in a cell, capture scrollY,
  type characters, capture scrollY again. Assert delta = 0.
- **Scenario 4 (wrapped)**: identify a cell whose text wraps. Click
  on visual line 2 of that cell. Verify the caret lands at a char
  offset corresponding to a position on line 2.

Each scenario is captured in `FINDINGS.md` with a status (GREEN /
YELLOW / RED) and a one-paragraph note. `STATUS.md` summarizes the
overall verdict.

---

## 4. What "GREEN" looks like

All four scenarios pass without us writing TextKit-internal code.
Specifically:
- No `NSTextLayoutFragment` subclass.
- No layout-manager delegate that re-implements positioning.
- No scroll suppression / scroll preservation hooks.
- No `ensureLayout` calls in click handlers.

If the four scenarios work using *only* `NSTextTable`,
`NSTextTableBlock`, and standard paragraph attributes, that's
GREEN. If we have to reach for any of the workarounds above, it's
not GREEN even if the visual result looks right — that pattern is
why we left TK2.

---

## 5. What "RED" looks like

Any one of:
- TK1 doesn't render the table correctly without us writing custom
  layout code (defeats the premise — switching means more custom
  code, not less).
- Click-to-caret in tables routes through code paths that need
  hand-rolled hit-testing.
- Typing in a cell triggers behavior we have to suppress (just
  like TK2 — we'd have moved to a different framework with the
  same class of issue).
- Wrapped-cell click positioning requires custom math.

If RED: hold the SuperSwiftMarkdownPrototype reference (CD-flagged
in D15.1 COMPLETE) as a candidate fallback, and consider whether
to rebuild the table surface differently in TK2 with that as a
guide.

---

## 6. Open questions for CD before/during spike

1. **Edit affordance**: TK1 cell editing is in-place (caret moves
   into the cell's flowed paragraph). Do we still want a
   Numbers-style "active cell border" affordance like D13's
   overlay? Or is in-place editing without the border acceptable?
   - Implication: if we want the border, that's still custom
     drawing on top of TK1 — but it's draw-only, not layout, so
     it doesn't fight the framework.
2. **Modal popout**: D13 added a right-click "Edit Cell in
   Popout…". Worth retaining once TK1 is in place? The original
   motivation (workaround for wrapped-cell limitation in D12)
   goes away if TK1 handles wrapping natively. Modal as a
   long-form-edit affordance still has merit; defer the call.
3. **Source fidelity**: TK1's `NSTextTable` doesn't natively know
   it's a markdown table. The serializer (NSAttributedString →
   markdown) is our responsibility either way; that's not a TK
   concern. Note for migration plan, not blocking the spike.

---

## 7. Schedule

This is a one-day spike. CD will not necessarily be available
during the work; the spike's job is to produce a clear
GREEN/YELLOW/RED verdict in `STATUS.md` and `FINDINGS.md` so the
migration decision can be made on the next CD touchpoint without
further synchronous discussion.

---

## 8. Out-of-scope (explicit non-goals)

- Migrating production code. The spike is standalone at
  `spikes/d16_textkit1_tables/`. Nothing in `Sources/` changes.
- Comparing performance to TK2.
- Building a markdown→TK1 parser. The spike hard-codes a single
  attributed string with table attributes; markdown ingestion is
  for the post-spike migration plan if GREEN.
- Source-reveal toggling. Out of scope per § 2.

---

## 9. Trace to foundation docs

- `docs/vision.md` Principle 3 (markdown today, structured formats
  tomorrow): tables are a structured-content concern. The wrong
  surface today blocks the structured-formats roadmap.
- `docs/stack-alternatives.md`: this spec implies an update to the
  "Text-editing engine" row IF the spike GREENs. Don't update
  pre-emptively.
- `docs/engineering-standards_ref.md` § 2.2: prohibits
  *accidentally* falling into TK1. The spike is a deliberate,
  scoped trial — the standard's intent (no silent code-path
  flips) is honored by the spike being explicit and isolated.