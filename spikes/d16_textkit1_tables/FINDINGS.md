# D16 Spike — Findings

Spike location: `spikes/d16_textkit1_tables/`
Run: `./run.sh` (logs → `/tmp/d16-spike.log`, harness command file → `/tmp/d16-command.json`)
Date: 2026-04-26

---

## Setup

Hard-coded `NSAttributedString` containing:
- 100-line plain-text preamble (so the table is below the initial viewport).
- One table built from `NSTextTable` + `NSTextTableBlock`. 4 columns, 13 rows (1 header + 12 body). One body row's cell content (row 4 col 2) is intentionally long enough to wrap to ~7 visual lines at the configured 200pt content width.
- 30-line postamble.

`NSTextView` configured explicitly via `NSTextStorage` → `NSLayoutManager` → `NSTextContainer` → init `NSTextView(frame:textContainer:)`. Confirmed at runtime via assertion that `textView.textLayoutManager == nil` and `textView.layoutManager` is `NSLayoutManager` (TK1).

No `NSTextLayoutFragment` subclass anywhere. No layout-manager delegate. No scroll suppression. No `ensureLayout` calls in click handlers.

---

## Scenario 1 — Render below initial viewport — **GREEN**

Initial viewport at y=0. Table starts at textView y≈1623. Programmatic scroll to y=1200 brought the header row to the top of the viewport. Snapshot at `/tmp/d16-shot-table.png` showed the full table grid drawn correctly: 4 columns with borders, 13 rows visible (header + 12 body). The wrapped-content cell (row 4 col 2) drew as 7 visual lines stacked vertically inside a single grid cell.

Compared to TK2: TK2 had `fragY=0` for fragments outside the initial visible area, leaving rows blank or mispositioned post-scroll. TK1 emitted correct geometry on the first layout pass.

---

## Scenario 2 — Click-to-caret — **GREEN**

Used `lm.glyphIndex(for: containerPoint, in: container)` to resolve the click. Synthesized clicks at the center of three cells; each resolved to a character index inside that cell's known range:

| Click view (x, y) | charIndex | Resolved cell | Range | In cell? |
|---|---|---|---|---|
| (240, 1763) | 1817 | row 4, col 1 (delta) | [1817, +5] | ✓ |
| (540, 1763) | 1845 | row 4, col 2 (wrap) | [1823, +201] | ✓ (visual line 1) |
| (540, 1811) | 1941 | row 4, col 2 (wrap) | [1823, +201] | ✓ (visual line 4) |

Initial click test landed in the wrong cell — that was a usage error (forgot to subtract `textContainerInset`). Once corrected, every click resolved cleanly.

Compared to TK2: TK2 needed `tlm.textLayoutFragment(for:)` against custom-fragment frames that could be stale after scroll. TK1 has stable glyph-space hit testing.

---

## Scenario 3 — Type without scroll jump — **GREEN**

Caret in cell row 4 col 1. scrollY = 1200. Inserted "abcde" → scrollY still 1200. Inserted newline → scrollY still 1200. Source length grew correctly (2775 → 2780 → 2781).

Compared to TK2: TK2 needed `scrollSuppressionDepth` guard around `keyDown` to prevent NSTextView's auto-scroll-to-caret. TK1 didn't move the viewport on insert because the caret was already in the visible region. (Probably TK1 also auto-scrolls when caret moves offscreen — that's the desirable behavior for navigation; not tested here because it's expected/wanted, not a bug.)

---

## Scenario 4 — Wrapped-cell click — **GREEN**

Wrapped cell (row 4 col 2) has range [1823, +201]; visual rect is 200pt wide × 112pt tall = 7 visual lines.

| Click view y | Visual line | charIndex | Offset within cell | Result |
|---|---|---|---|---|
| 1763 | 1 (top) | 1845 | 22 of 201 | ✓ |
| 1811 | 4 (middle) | 1941 | 118 of 201 | ✓ |
| 1859 | 7 (just past) | 2030 | 207 of 201 | landed in col 3 (next cell, expected — y=1859 is past the wrap cell's bottom edge of 1855) |

The middle-line click (y=1811, offset 118) is the canonical D12-defeating case: click on visual line 2+ of a wrapped cell. TK1 resolved it without custom math.

Compared to TK2: D12 + D13 needed `cellLocalCaretIndex` (Core Text framesetter math) to figure out which wrapped line was clicked. TK1's `glyphIndex(for:)` does it natively because TK1's flowed paragraphs in cells have ordinary glyph runs.

---

## Other observations

- **Programmatic scroll**: `scrollView.contentView.scroll(to:)` worked normally; no fragment lazy-layout artifacts surfaced (no equivalent of TK2's "scroll one detent and the table disappears").
- **Wrap behavior**: `NSTextTableBlock.setContentWidth(_, type: .absoluteValueType, for: .padding/.border)` controls cell sizing; `setContentWidth` directly governs the column's content width (and TK1 wraps inside it). Behaved as documented.
- **Borders**: `block.setBorderColor(.separatorColor)` and `setWidth(1, type: .absoluteValueType, for: .border)` produced the grid lines visible in the snapshot.
- **Cell character range**: each cell ends with `\n` (paragraph terminator). The cell's "text range" excludes that terminator. Click at the very end of a cell (e.g., past the last visual char) lands on the terminator, which means the next cell — design choice for the hit-test algorithm, not a bug.

---

## Cost-of-migration signals

What a TK1 migration retires from the current production code:
- `Sources/Editor/Renderer/Tables/TableRowFragment.swift` — entire custom NSTextLayoutFragment subclass.
- `Sources/Editor/Renderer/Tables/TableLayoutManagerDelegate.swift` — entire delegate.
- `Sources/Editor/Renderer/Tables/TableLayout.swift` — most of it; only the markdown→cell-content conversion stays (in a different shape).
- `Sources/Editor/LiveRenderTextView.swift`'s `scrollSuppressionDepth` + `scrollRangeToVisible` override + `ensureLayout` in mouseDown.
- `Sources/Editor/EditorContainer.swift`'s `ensureLayout(documentRange)` after every `renderCurrentText`.
- D13's `CellEditOverlay`, `CellEditController`, `CellEditModalController` — the overlay machinery exists because TK2 couldn't edit wrapped-cell content in place; TK1 doesn't need it.

Kept:
- Workspace shell (folder tree, tabs).
- Save/Save As (D14).
- D9 reveal-at-line.
- D10 line numbers / D11 CLI flags.
- Markdown parser feeding the renderer (output shape changes — emits `NSAttributedString` with table attributes instead of TK2 fragment metadata).
- Debug HUD (carries forward; toolbar wiring is independent of TextKit version).

What gets revisited:
- D8.1 source-reveal — UX consideration, not architectural; TK1 supports either approach.
- Cell-aware nav (Tab/arrows in D12) — TK1 may or may not need help; not tested in this spike.
- Active-cell border (D13 §3.7) — separate drawing concern, not tied to the layout system.

---

## Recommendation

**Proceed with TK1 migration.** All four canonical scenarios work using stock TK1 APIs with no NSTextLayoutFragment subclass, no layout-manager delegate, no scroll suppression, and no `ensureLayout` calls in click handlers. The migration retires a substantial slice of D8/D12/D13's table machinery in exchange for a markdown→TK1-attributed-string converter that's narrower than the rendering layer it replaces.

Risk register for the migration plan:
- TK1's `NSLayoutManager` API is documented as functional but not the "modern" path — watch for deprecation warnings in build output and document them as known constraints.
- Cell content is a paragraph terminated by `\n`. If the markdown-source surface needs to round-trip cell content with embedded newlines, the converter has to escape/unescape consistently (same problem we already solve in D13's pipe-escaping).
- Tab/arrow nav between cells not validated in this spike — assume it needs the same kind of small custom helper D12 had, but cheaper to build on top of TK1's stable glyph indexes.

Next: write the D17 migration triad (spec + plan + prompt). Spike code stays at `spikes/d16_textkit1_tables/` as the reference implementation.
