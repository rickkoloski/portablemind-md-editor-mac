# D8.1: Table Reveal on Caret-In-Range — COMPLETE

**Shipped:** 2026-04-24
**Spec:** `docs/current_work/specs/d08_1_table_reveal_spec.md`
**Plan:** `docs/current_work/planning/d08_1_table_reveal_plan.md`
**Builds on:** D8 grid rendering (commit `99dc2a9`)

---

## What shipped

Caret-driven reveal for GFM tables. When the caret enters any character inside a table's source range, that table's rows switch from the `TableRowFragment` grid to default text rendering so the pipe-delimited source becomes visible and editable. When the caret leaves, the grid re-renders with whatever edits were made.

Reveal granularity is **whole-table**, matching the CodeBlock pattern:

- Click into any cell of any row → that entire table reveals.
- Arrow / click out of the table → grid returns.
- Two tables in one doc reveal independently — entering B hides A.
- Typing inside a revealed table updates the source; re-render on each keystroke keeps the displayed text stable (no flicker).
- Source buffer is never modified by reveal state — only paragraph-style attributes on existing rows plus TextKit 2 fragment invalidation.

---

## Files modified

| File | Change |
|---|---|
| `Sources/Editor/Renderer/Tables/TableLayout.swift` | Added `tableRange: NSRange` property + initializer parameter. Carries each table's full source span so reveal-state transitions know what to invalidate. |
| `Sources/Editor/Renderer/MarkdownRenderer.swift` | `visitTable` passes `tableRange` into `TableLayout.init`. Also attaches a min/max-line-height `NSParagraphStyle` to every tagged row so hit-testing bounds match the grid's claimed layout height (see Finding #1). |
| `Sources/Editor/Renderer/Tables/TableLayoutManagerDelegate.swift` | Added `revealedTables: Set<ObjectIdentifier>`. Delegate method returns a default `NSTextLayoutFragment` (instead of `TableRowFragment`) when the row's layout ID is in the set. |
| `Sources/Editor/EditorContainer.swift` | Coordinator gained `revealedTableLayoutID` + `updateTableReveal(in:)`, driven from `textViewDidChangeSelection`. Transition path strips/restores paragraph-style height, flags `.editedAttributes` on the storage to drop cached fragments, and invalidates the `NSTextRange` for each affected table. |

No new `.layoutManager` references (grep of `Sources/` shows only existing docstrings enforcing §2.2).

---

## Implementation flow

On every selection change `textViewDidChangeSelection`:

1. Probe `TableRowAttachment` at the caret offset via `textStorage.attribute(TableAttributeKeys.rowAttachmentKey, ...)`.
2. Compute `newLayoutID = ObjectIdentifier(attachment.layout)`; compare against `revealedTableLayoutID`.
3. If changed, mutate `delegate.revealedTables`:
   - Remove the old ID (if any).
   - Add the new ID (if any).
4. For each affected table, adjust per-row paragraph style:
   - Revealed → remove `.paragraphStyle` so source uses natural line heights.
   - Un-revealed → re-apply the same min/max-line-height style the renderer used originally (from `TableLayout.rowHeight`), so when the grid returns it has the same flow-layout footprint.
5. Inside a `beginEditing()`/`endEditing()` transaction on `NSTextStorage`, flag `.editedAttributes` on each clamped range AND call `NSTextLayoutManager.invalidateLayout(for:)` on the corresponding `NSTextRange`.
6. `textViewportLayoutController.layoutViewport()` + `needsDisplay = true` to force the re-layout cycle in the current run loop.

A helper `findTableRange(for:in:)` scans storage for any row whose attachment layout ID matches a given ID. That's needed because after a renderCurrentText pass, the `TableLayout` instance held by `revealedTableLayoutID` refers to the pre-edit layout; the post-edit storage carries a different `TableLayout` instance at the same source span. Scanning storage finds the current table range under that stored ID (if it still exists).

---

## Findings

**#1 — `invalidateLayout(for:)` alone doesn't re-fragment; `.editedAttributes` does.** First pass only called `NSTextLayoutManager.invalidateLayout(for:)` on the affected range. TextKit 2 kept its cached fragments and the delegate was never re-consulted — the grid kept drawing even though `revealedTables` had changed. The working pattern is: wrap the transition in `NSTextStorage.beginEditing()` / `endEditing()`, call `storage.edited(.editedAttributes, range:, changeInLength: 0)` on each target range, and then still call `invalidateLayout(for:)` on the `NSTextRange`. The `.editedAttributes` notification flows through `NSTextContentStorage` to drop cached fragments; the invalidation schedules re-layout of the viewport. Both are needed.

**#2 — Grid rows need a paragraph style that claims the grid's layout height, not just `layoutFragmentFrame`.** Before D8.1, rows only had `TableRowFragment.layoutFragmentFrame` overriding the visual height. Hit-testing in the "dead zone" between the natural ~18pt line height and our claimed grid height (~35pt+) hit no line fragment → the caret couldn't be placed by clicking inside the grid at all. Fix: at render time, attach an `NSParagraphStyle` with `minimumLineHeight` and `maximumLineHeight` both set to the row's computed grid height. The underlying text line now spans the grid bounds, hit-testing resolves to it, and the caret lands in the row's source range. This fix also clicks into D8 itself — the grid was visually correct but functionally unclickable until D8.1 added the paragraph style.

**#3 — On reveal transitions, the paragraph style has to be stripped and restored to match the fragment it's under.** If revealed rows keep their 35pt-min-line-height paragraph style, the default `NSTextLayoutFragment` honors it and draws 35pt-tall lines of pipe source (ugly whitespace above/below). If un-revealed rows drop it, the grid fragment has no flow-height anchor and the viewport under-provisions space for the grid. Solution: `adjustParagraphStyles(in:revealed:storage:)` enumerates the row attachments and strips `.paragraphStyle` on reveal, restores the grid-height style on un-reveal. Done as part of the same `beginEditing`/`endEditing` transaction so the attribute edit + fragment drop + layout invalidation land together.

**#4 — Stale-layout lookup after renderCurrentText.** Every keystroke inside a revealed table triggers a full re-render (markdown → attributes), producing a new `TableLayout` instance at the same source span. When the user then arrows out of the table, the Coordinator's stored `revealedTableLayoutID` refers to the *old* layout instance whose storage no longer exists in attributes. Looking it up by object-identity would miss. Fix: `findTableRange(for:in:)` scans storage attributes for *any* row whose current layout's `ObjectIdentifier` matches the stored one; if found, use that layout's `tableRange`; if not found (because the table was re-rendered and replaced), fall back to clearing the delegate entry and moving on. In practice the re-render path puts a new layout at the same range, so the scan finds the new instance by identity only while reveal is active — after reveal flips off, the old ID is dropped.

**#5 — Dogfood is the hit-test test.** `xcodebuild build` green confirms the compile; it doesn't tell you a click into a 35pt-tall fragment lands on a line fragment. That requires launching the app and clicking. Finding #2 was invisible in build output and only visible when the click produced no caret.

---

## Deviations from spec + plan

- **Added paragraph-style manipulation to the reveal pipeline.** The spec's design §3.2–§3.5 described attachment / identity / range tracking but didn't anticipate that the grid's click-ability depended on a paragraph style at the text-storage layer. The plan's Step 5 assumed `invalidateLayout(for:)` alone would re-fragment; it didn't. Both are now threaded together in `updateTableReveal` / `adjustParagraphStyles`. No change to the *user-visible* spec; implementation is more invasive than anticipated.
- **`findTableRange(for:in:)` helper added** as a fallback for stale-identity lookup after renderCurrentText replaces the `TableLayout` instance. Not in the plan; surfaced during dogfood.
- **`.editedAttributes` signaling added** — same reason. The plan assumed `invalidateLayout(for:)` would be sufficient on its own.

None of these change the behavior contract; they're implementation honesty about TextKit 2's caching.

---

## Verification

- Build green via `xcodebuild … build`.
- `grep -r '\.layoutManager' Sources/` returns only existing docstring warnings — no new production references.
- Dogfood on `docs/roadmap_ref.md`:
  - Click into the Status cell of any row → whole roadmap table reveals pipe-source.
  - Type a character in a cell — appears in source, grid re-computes on each keystroke (expected), no flicker.
  - Arrow down past the last row → grid returns with the edit.
  - Click in `competitive-analysis.md` across two tables → first hides, second reveals.
- D8 grid rendering unchanged when caret is outside any table.
- D9 scroll-to-line, D10 line numbers toggle, D11 CLI view-state all still work.
- Delimiter reveal (`#`, `**`) unchanged — CursorLineTracker runs alongside `updateTableReveal` without conflict.

---

## Deferrals / known gaps

| Gap | Disposition |
|---|---|
| **Structured single-cell editing** — click a cell, edit just that cell (not the whole-table pipe source) | **Backlog** on Harmoniq project #53 (see Harmoniq section below). Spec §2 explicitly listed this as out of scope for D8.1. |
| Per-row reveal (vs. whole-table) | Deferred; revisit only if dogfood surfaces a use case. |
| Animated grid ↔ source transition | Out of scope. |
| Header-only reveal ("edit header names, keep body as grid") | Out of scope. |
| `CellRenderer` protocol / pluggable cells / inline markdown inside cells | D8 deferral; still deferred. |

---

## Harmoniq

D8.1's completion plus the one explicitly-deferred behavior (structured single-cell editing) was filed as a backlog task on PortableMind project #53. That task documents the UX problem (pipe-source edit mode is powerful but not what Word/Docs users expect) and references this COMPLETE doc for context.
