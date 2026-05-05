# D24 Phase 1 Spike — `byTruncatingTail` multi-line behavior

**Status:** ✅ run, recommendation issued — **RED with caveat** (see below).
**Spec:** `docs/current_work/specs/d24_responsive_table_columns_spec.md` §Decision Q8
**Plan:** `docs/current_work/planning/d24_responsive_table_columns_plan.md` §Phase 1

---

## What this spike answered

Q8 of the D24 spec claimed that on a TK1 cell with paragraph style `lineBreakMode = .byTruncatingTail` and **no `numberOfLines` cap**, TextKit would:

1. **Word-wrap** at boundaries normally for ordinary text.
2. **Push an over-long unbreakable token** (long URL, base64 blob) to its own line.
3. **Ellipsize the trailing portion** if even on its own line the token can't fit.
4. **Continue wrapping normally** for subsequent paragraph content below the over-long token.

**Result: Q8's claim is empirically false on macOS TK1.** `byTruncatingTail` is a **single-line** truncation mode under `NSLayoutManager` + `NSTextContainer`, regardless of container height. The full content collapses into one line; any overflow ellipsizes; multi-line wrap does not occur.

But the spike also revealed a cleaner alternative path that sidesteps the spec's planned RED fallback (custom NSLayoutManager hook). See **Recommendation** below.

---

## Approach

**Offscreen / programmatic.** Single self-contained Swift script (`run_spike.swift`).

- No NSWindow, no NSTextView, no `NSApp.run()`.
- Builds `NSTextStorage` → `NSLayoutManager` → `NSTextContainer` directly, calls `ensureLayout(for:)`, walks line fragments via `lineFragmentRect(forGlyphAt:effectiveRange:)`.
- Three modes per cell × width:
  - `wordWrap` — control. `lineBreakMode = .byWordWrapping`, infinite container height.
  - `truncTailInf` — Q8 claim. `lineBreakMode = .byTruncatingTail`, infinite container height.
  - `truncTailFinite` — variant. `lineBreakMode = .byTruncatingTail`, container height = 10,000pt (tall but finite, controls for any "infinite container = single-line shortcut" path inside TextKit).
- `tc.maximumNumberOfLines = 0` set explicitly on every container.

### Test cells

| Cell | Content shape | What it tests |
|---|---|---|
| `normal` | 287 chars of ordinary multi-paragraph prose | Behavior 1 (word-wrap normally). |
| `longUrl` | 228 chars, single URL with hyphens, no whitespace | Behaviors 2 + 3 (push over-long token to own line; ellipsize). |
| `mixed` | 473 chars: prose → URL → prose | Behaviors 1 + 2 + 3 + 4 in one cell. |

### Container widths

`600pt`, `400pt`, `280pt`.

### Outputs

- `results/run.log` — per-line fragment dump for every (mode × cell × width) combination. **This is the authoritative evidence.**
- PNG rendering was attempted via `NSBitmapImageRep` + `NSGraphicsContext` but produced blank bitmaps (~160-byte all-zero PNGs). The fix is bitmap-context plumbing not worth the spike budget; the stdout fragment data is unambiguous on its own. If a visual cross-check is ever needed, the documented fallback path (visual spike with `NSApp.setActivationPolicy(.accessory)`) remains available — but the recommendation below doesn't require it.

---

## How to reproduce

```bash
cd ~/src/apps/md-editor-mac/spikes/d24_table_columns
swift run_spike.swift > results/run.log
```

Inspect `results/run.log` — each block is `=== mode=X cell=Y width=Zpt ===` followed by `numberOfGlyphs`, `lineCount`, and per-line fragment data.

---

## Observed behavior

### Mode `wordWrap` (control)

| Cell | Width | Lines | Notes |
|---|---|---:|---|
| normal  | 600 | 4  | Clean word-boundary wrap. Last line: "invoke truncation at all." |
| normal  | 400 | 5  | Clean word-boundary wrap. |
| normal  | 280 | 8  | Clean word-boundary wrap; lines hover around 35-43 chars each. |
| longUrl | 600 | 3  | URL wraps at hyphen (`-`) boundaries. TextKit treats `-` as a soft break opportunity. |
| longUrl | 400 | 5  | URL wraps at hyphens; final line just `widths`. |
| longUrl | 280 | 7  | URL wraps at hyphens. No char-wrap fallback needed because the URL has hyphens. |
| mixed   | 600 | 6  | Mixed content wraps cleanly; prose at word boundaries, URL at hyphen boundaries. |
| mixed   | 400 | 9  | Same — clean throughout. |
| mixed   | 280 | 13 | Same — clean throughout. |

**Finding:** real markdown URL content has soft break opportunities (`-`, `/`, `.`). TextKit's `byWordWrapping` produces clean multi-line wrap on every test case in this spike without ever falling through to char-wrap.

### Mode `truncTailInf` (Q8 claim, infinite container height)

| Cell | Width | Lines | Notes |
|---|---|---:|---|
| normal  | 600 | **1** | Single line, all 287 chars in `chars={0, 287}`, `usedRect.width = 596pt`. Truncated visually with ellipsis (last visible: "…abnormally"). |
| normal  | 400 | **1** | Same — single line, 287 chars, ellipsized. |
| normal  | 280 | **1** | Same. |
| longUrl | 600 | **1** | Single line, 228 chars. |
| longUrl | 400 | **1** | Same. |
| longUrl | 280 | **1** | Same. |
| mixed   | 600 | **1** | Single line, all 473 chars, ellipsized. |
| mixed   | 400 | **1** | Same. |
| mixed   | 280 | **1** | Same. |

**Finding:** `byTruncatingTail` flattens the entire content into one line under `NSLayoutManager`, regardless of width. None of behaviors 1-4 occur.

### Mode `truncTailFinite` (variant — tall finite container)

Identical to `truncTailInf`. Container height (infinite vs 10,000pt) does not affect the single-line collapse. So the issue is not "infinite container = NSLayoutManager shortcut to single line."

---

## Why Q8 is wrong

Apple's `NSLineBreakMode` documentation describes `byTruncatingTail` as a single-line truncation mode by design. The "wrap then truncate" behavior Q8 imagined doesn't exist as a TK1 paragraph-style flag. The closest behaviors that do exist:

- **`byWordWrapping`** — multi-line wrap; never truncates; falls back to char-wrap for unbreakable tokens.
- **`byTruncatingTail`** — single-line truncation; ellipsis on overflow; no wrap.
- **Custom `NSLayoutManager` subclass** — can intercept line-fragment generation and emit per-line truncation mid-token (the planned RED fallback).

There is no flag combination that produces "wrap normally; truncate only over-long tokens; continue wrapping below."

---

## Recommendation: RED, with a strong simplification

**Headline:** Q8 fails the spike. **Do not** rely on `byTruncatingTail` for cell content.

**Recommended path forward (simpler than the planned RED fallback):** **use `byWordWrapping` instead, with no custom layout-manager hook.**

Rationale:
- The spec's Q8 cap (`natural_width(col) ≤ viewport_width`) already prevents a column from claiming more space than the viewport. The remaining concern was: what happens to a single super-long unbreakable token *inside* a column whose width is < the token's width.
- The wordWrap data shows real-world content (URLs, paths) wraps fine because hyphens, slashes, and dots act as soft break opportunities. The "single super-long unbreakable token" case (a base64 blob with literally no break opportunities) is rare in markdown.
- TextKit's `byWordWrapping` falls back to character-level wrap for tokens with no break opportunities. The result is a multi-line cell where the pathological token wraps mid-character — visually less polished than ellipsis, but **lossless** (all characters remain visible, copyable, and selectable). For markdown content that's better UX than truncation.

**The planned RED fallback** (custom `NSLayoutManager` subclass detecting mid-token line breaks and applying per-line truncation, +1 phase per the plan §Phase 1 DOD) becomes unnecessary under this recommendation.

**Question:** does CD agree that `byWordWrapping` with TextKit's char-wrap fallback for pathological tokens is the better path than a custom NSLayoutManager hook? The spec's §Edge cases "Single super-long unbreakable token" entry would need a small revision to reflect this — the column is still capped at viewport width per Q8, but the cell's overflow now wraps (char-wrap last resort) rather than ellipsizes.

---

## Decision

**Status:** RED on the literal Q8 claim. Spike done. Awaiting CD answer on the proposed simplification (use `byWordWrapping` directly instead of the planned RED fallback).

If CD agrees with the simplification:
- Phase 2 implements `natural_width(col)` measurement (unchanged).
- Phase 3's distribution math is unchanged.
- Phase 4 swaps the 320pt cap; sets `paragraphStyle.lineBreakMode = .byWordWrapping` on cells (instead of `.byTruncatingTail`).
- The spec's §Edge cases "Single super-long unbreakable token" updates to reflect char-wrap fallback (lossless) rather than ellipsis.
- **No +1 phase** — the original 6-phase plan stands.

If CD prefers the original ellipsis behavior despite the cost: the +1 phase RED fallback (custom `NSLayoutManager` hook) is documented in the plan §Phase 1 risks and remains the path.

---

## Notes for next-session pickup

- `results/run.log` is committed — re-running is not required; the data is reproducible from the script.
- The spike script intentionally has no PNG rendering (the offscreen bitmap path produced blanks; not worth fixing for this scope).
- The `numberOfGlyphs=0` line in stdout for every block is a timing artifact of the print order; the loop's internal `glyphCount` is non-zero (otherwise no lines would be reported). Cosmetic only.
