# D16 — Status: GREEN

**Verdict**: TextKit 1 native tables resolve all four scenarios that defeated TK2 across D8–D15.1, with no custom layout code.

## Phase results

| Phase | Scenario | Result |
|---|---|---|
| 1 | Project skeleton (TK1 confirmed, app launches) | ✓ |
| 2 | Render below-viewport table — scroll into view | **GREEN** |
| 3 | Click-to-caret in cells | **GREEN** |
| 4 | Type without scroll jump | **GREEN** |
| 5 | Wrapped-cell click resolution | **GREEN** |
| 6 | Findings + status (this) | **GREEN** |

## Confidence

High. Each scenario was verified with explicit assertions (cell character ranges, scroll deltas) — not just visual confirmation. The mechanism is also clear: TK1 lays out cell paragraphs with ordinary glyph runs, so all the standard NSLayoutManager APIs (glyphIndex(for:), boundingRect(forGlyphRange:in:), etc.) work without us reimplementing them.

## What we cut from the production codebase if we proceed

- Custom NSTextLayoutFragment subclass for tables.
- Layout-manager delegate that returned the custom fragment.
- Scroll-suppression depth counter + scrollRangeToVisible override on the text view.
- ensureLayout calls in mouseDown and renderCurrentText.
- D13 cell-edit overlay machinery (overlay, controller, modal popout).
- Custom CellLocalCaretIndex Core Text math.

## What gets reused

- Markdown parser (output shape changes).
- Workspace shell, save/save as, line numbers, scroll-to-line.
- Debug HUD (independent of TextKit version).
- Harness regression scaffolding (the shape carries to TK1; assertions about "where did the click land" are valid in either world).

## Recommendation

Stop here. Write the D17 migration triad and execute it. SuperSwiftMarkdownPrototype reference can be retired from the active fallback set — TK1 cleared the bar.
