# D12 Spike Findings — Cell-Level Caret Routing

**Date:** 2026-04-24
**Timebox:** 1 day — completed in ~2 hours
**Plan reference:** `docs/current_work/planning/d12_per_cell_table_editing_plan.md` § Phase 1
**Outcome:** GREEN on revised hypothesis (custom `NSTextSelectionDataSource`).

---

## Summary

The plan's original hypothesis (§3.4 primary: override `NSTextLayoutFragment.textLineFragments` with custom typographic bounds) was invalidated by header reading alone — `NSTextLineFragment.typographicBounds` and `glyphOrigin` are readonly, with no public setter path.

A revised hypothesis — replace `NSTextLayoutManager.textSelectionNavigation` with one backed by a custom `NSTextSelectionDataSource` that overrides `enumerateCaretOffsetsInLineFragmentAtLocation:usingBlock:` — was tested via a minimal SwiftPM spike (`spikes/d12_cell_caret/`) and is **GREEN**: NSTextView honors our custom caret x-values when drawing the caret.

D12 can proceed with this approach. NSTextField overlay fallback is not needed. Modal break-glass remains explicitly parked.

---

## Finding #1 — Plan §3.4's original hypothesis is invalidated by header reading alone

`AppKit.framework/Headers/NSTextLineFragment.h` declares:

```objc
@property (readonly) CGRect typographicBounds;   // readonly
@property (readonly) CGPoint glyphOrigin;        // readonly
```

No public setter. The designated init is `initWithAttributedString:range:`; bounds come from CT layout of the attributed string, with no `bounds:` parameter. Even if we override `textLineFragments` as a computed property on an `NSTextLayoutFragment` subclass, we cannot synthesize `NSTextLineFragment` instances whose bounds are disconnected from their attributed-string CT layout.

Conclusion: the specific mechanism the plan named cannot be built. Spike's answer on that hypothesis is RED, from headers alone, no code written.

---

## Finding #2 — `NSTextSelectionDataSource` is on the caret-drawing hot path

The alternative approach — surfaced during header exploration — uses `NSTextLayoutManager.textSelectionNavigation` (a mutable property on `NSTextLayoutManager`) to install an `NSTextSelectionNavigation` backed by a custom `NSTextSelectionDataSource`. Two protocol methods matter:

```objc
- (void)enumerateCaretOffsetsInLineFragmentAtLocation:(id<NSTextLocation>)location
                                           usingBlock:(void (^)(CGFloat caretOffset,
                                                                id<NSTextLocation> location,
                                                                BOOL leadingEdge,
                                                                BOOL *stop))block;

- (nullable NSTextRange *)lineFragmentRangeForPoint:(CGPoint)point
                              inContainerAtLocation:(id<NSTextLocation>)location;
```

Observed behavior in the spike (macOS 15.x, Xcode 16, TextKit 2 NSTextView `initUsingTextLayoutManager:true`):

- Both methods are called by NSTextView on every click and on every selection change. Confirmed via `[CELL-DS]` log lines.
- When `enumerateCaretOffsetsInLineFragment` yields a monotonic x-table (x = 50 + 30·srcIdx), the caret **visually draws at our x-values**, not at natural CT layout positions. Verified by:
  - Rick clicked at text-view x=249.2.
  - NSTextView resolved selection to source offset 6 (cell insertion of typed "a" produced `| cella one | cell two |`).
  - After insert, selection advanced to source offset 7.
  - Our table for offset 7 returns x=260.
  - Observed caret drew at visual x≈256 (eyeballed from screenshot; within measurement tolerance of 260).
  - Natural CT x for offset 7 in the new source would be ~110 (inside the first cell, after "cella"). Caret was NOT there.

The dissociation between source-offset (correct) and visual caret x (custom) is exactly what D12 needs: source remains truth; cell-visual caret placement is controlled by the data source.

### Subtlety: click-to-source-offset mapping is not a pure nearest-x lookup

Rick's click at x=249.2 landed at source offset 6 (our table: x=230, distance 19.2). Offset 7 (our table: x=260, distance 10.8) was closer in our x-space but NOT picked.

Hypothesis: NSTextView's click-routing consults `lineFragmentRangeForPoint` first to determine which line fragment the click hits; that call fell back to the default in our spike (returned the whole row's natural line fragment). Then NSTextView picks the character offset whose natural CT-layout x is closest to the click point — not the offset whose *custom* caret x is closest.

Implication for D12: the `lineFragmentRangeForPoint` override must return a cell-specific source range (not fall back to the full row) if we want clicks to route by grid geometry instead of natural CT layout. This is in the original spec §3.3 and plan Step 4; spike confirms the override surface exists and is consulted on every click.

---

## Finding #3 — `NSTextSelectionDataSource`'s enumeration must be in visual (left-to-right) order

First spike attempt yielded non-monotonic x-values (cell 1 values interleaved with cell 2 values in source order). NSTextView's behavior was confused — selection landed at offsets that weren't the nearest-x in our table. Header comment:

> Enumerates all the caret offset from left to right in visual order.

When the spike was simplified to monotonic x = 50 + 30·srcIdx (strictly left-to-right), selection resolved cleanly to offsets near the click's x.

Implication for D12: the production override must sort cell ranges by visual x before enumerating, and within each cell enumerate source offsets in the cell's visual order (LTR). For GFM tables this is straightforward (cells always render left-to-right), but the ordering discipline needs to be explicit in the implementation.

---

## Finding #4 — TextKit 2 `NSTextView` setup without a scroll view is viable for spikes

Initial spike used `NSScrollView` containing `NSTextView(usingTextLayoutManager: true)`, but clicks mapped through NSScrollView produced text-view coordinates with negative y (text view origin positioned off the visible scroll area). Dropping the scroll view and placing the text view directly in the window's content view resolved the coordinate system and made the spike testable.

Not a production constraint — production uses the scroll view intentionally for the document viewport. Just a spike simplification note for future throwaways.

---

## Verdict

- **Green** on the revised hypothesis (custom `NSTextSelectionDataSource` controls caret x-drawing).
- **No need for overlay fallback** in the D12 spec. Overlay stays documented as a theoretical fallback in case production-scale integration surfaces problems, but is not the primary path.
- **Modal fallback remains explicitly parked** per CD direction.

---

## Revisions required to spec / plan

### Spec `d12_per_cell_table_editing_spec.md`

- §3.4 — replace the "override `textLineFragments`" approach with "install custom `NSTextSelectionNavigation` using `CellSelectionDataSource`." Describe the two overridden methods and their contracts.
- §3.4 — remove NSTextField overlay as the *only* fallback; keep it only as a speculative remote-possibility fallback if production integration surfaces issues with large documents.
- §3.5 — clarify that caret height is fixed by removing the min/max-line-height paragraph style on revealed tables (unchanged), but that cell-mode caret height is governed by the natural line fragment bounds of the source line (which have natural font height since we don't add any height-forcing attribute).
- §5 step reorder — the DataSource installation step replaces the "line-fragment override" step.
- §6 Q1 — answered GREEN by spike; retire the open question.
- §6 add — new subtlety about click-routing depending on `lineFragmentRangeForPoint` returning cell-scoped ranges, not row-scoped.

### Plan `d12_per_cell_table_editing_plan.md`

- Phase 2 Step 2 retitled: "`CellSelectionDataSource` — custom NSTextSelectionDataSource routing caret x to cell geometry."
- Phase 2 Step 3 (renderer paragraph style) — unchanged.
- Phase 2 Step 4 (single-click routing) — `mouseDown` override can probably be removed; NSTextView's default click handling delegates through the custom navigation. To be confirmed in production integration.

### D12 prompt `d12_per_cell_table_editing_prompt.md`

- Update the reference to the spike path and its GREEN result.
- Swap "line-fragment override" constraint wording with "custom data source" wording.

---

## Spike-code disposition

Spike code is committed alongside this FINDINGS.md (following the `spikes/d01_textkit2/` precedent). Build artifacts (`.build/`) are gitignored. The source is ~300 lines and useful as a re-runnable reproducer if the underlying TextKit 2 behavior changes in a future macOS release.

To re-run:

```bash
cd spikes/d12_cell_caret
swift run
```

Click and type in the window; watch `[CELL-DS]` and `[EVENT]` lines in the terminal.
