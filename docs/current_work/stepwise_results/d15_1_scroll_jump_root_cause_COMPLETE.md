# D15.1: Scroll Jump on Typing — Root-Cause Investigation

**Shipped:** 2026-04-26 (follow-up to D15)
**Outcome:** Partial fix in place; **TK2 path retired** in favor of TK1 spike (D16).

> **Status:** D15.1 closed all reproducible harness scenarios but visual bugs persisted in real-user dogfooding. Tail of investigation revealed the underlying issue — TextKit 2 lazy-layout-with-custom-fragment-heights — to be architectural, not a coding mistake. See "Pivot to TextKit 1" below.

---

## Why D15 didn't actually fix it

D15 captured `scrollView.contentView.bounds.origin.y` inside `renderCurrentText` (which runs INSIDE `textDidChange`), then restored it on the next runloop tick. The harness verification looked GREEN.

CD reported the bug still surfaces under real keystrokes:
- Type a space or Enter mid-paragraph in a long doc → viewport jumps.
- Type Enter inside a cell-edit overlay → viewport jumps even further.

Two D15 oversights:

1. **Capture happens too late.** NSTextView's internal auto-scroll-to-caret fires synchronously inside `super.keyDown` BEFORE `textDidChange` is called. By the time the D15 capture runs, scrollY already reflects the auto-scrolled position. Restoring "preserved Y" just locks in the post-jump value.

2. **Harness reproduction used the wrong path.** `tv.insertText(_:replacementRange:)` (the harness's `insert_text` action) doesn't trigger NSTextView's keyDown-driven auto-scroll. The test passed because the bug never fired.

---

## Root cause

NSTextView, when its selection moves on a content-modifying key event, calls `scrollRangeToVisible(_:)` on itself to keep the caret in view. For a user typing in the middle of an already-visible region, that scroll is a no-op intent — but TextKit 2's full-storage re-attribute (our `renderCurrentText`) reflows the document between the auto-scroll capture and the layout pass, leaving the clip view in an inconsistent state. User sees a "jump."

For Enter inside a cell-edit overlay, a second issue compounds it: the host text view's `selectedRange` was never moved when the overlay was mounted, so it still pointed at wherever the caret was BEFORE the user clicked the cell. When `commit()` calls `makeFirstResponder(host)` during teardown, NSTextView auto-scrolls to that stale selection — possibly far offscreen.

---

## Fix

### Fix A — block NSTextView's auto-scroll-to-caret during typing

Override `scrollRangeToVisible(_:)` on `LiveRenderTextView` with a depth-counter guard. In `keyDown(with:)`, set the guard around `super.keyDown` for content-modifying keys; bypass for navigation keys (arrows, page, home/end) so they retain natural follow-the-caret scrolling.

```swift
var scrollSuppressionDepth: Int = 0

override func scrollRangeToVisible(_ range: NSRange) {
    if scrollSuppressionDepth > 0 { return }
    super.scrollRangeToVisible(range)
}

override func keyDown(with event: NSEvent) {
    // ... cell-aware nav unchanged ...
    let suppress = !Self.isNavigationKey(keyCode: event.keyCode)
    if suppress { scrollSuppressionDepth += 1 }
    super.keyDown(with: event)
    if suppress {
        DispatchQueue.main.async { [weak self] in
            self?.scrollSuppressionDepth = max(0, (self?.scrollSuppressionDepth ?? 0) - 1)
        }
    }
}
```

### Fix B — anchor host selection to the clicked cell

In `CellEditController.showOverlay`, set `host.selectedRange` to `cellRange.location` BEFORE handing focus to the overlay. After `commit()` returns focus to the host, the host's selection is now inside a cell that was just clicked (and is therefore visible) — `makeFirstResponder` has nothing to scroll to.

Plus a belt-and-suspenders: increment `scrollSuppressionDepth` around the storage edit + render + teardown in `commit()`, async-clear after.

---

## Verification

Three harness tests, using `synthesize_keypress` (a new harness action that dispatches a real `NSEvent.keyEvent` through `keyDown(with:)` — exercises the same machinery as a physical keystroke, unlike `insertText`):

| Test | Setup | Result |
|---|---|---|
| Path A | scrollY=600, set selection mid-doc, type space + return + 5 letters via real keyDown | scrollY=600 across all 7 keypresses; chars actually inserted (length 12707 → 12714) |
| Path B realistic | scrollY=250 (table visible), mount overlay on cell, type X, commit | scrollY=250 held |
| Path B unrealistic | scrollY=600, mount overlay on offscreen cell, commit | scrollY → 250 (auto-scrolls to where the user is editing — correct behavior, not a regression) |

The path B unrealistic case scrolls to the cell because the fix's host-selection anchor pulls the viewport to where the user just edited. In a real session you can't click an offscreen cell, so this is theoretical only.

---

## Files modified

- `Sources/Editor/LiveRenderTextView.swift` — `scrollSuppressionDepth` + `scrollRangeToVisible` override + `keyDown` guard wrap + `isNavigationKey` helper.
- `Sources/Editor/Renderer/Tables/CellEditController.swift` — host selection anchor in `showOverlay`; suppression-depth increment around `commit()` body.
- `Sources/Debug/HarnessCommandPoller.swift` — `synthesize_keypress` action (dispatches real `NSEvent.keyEvent` through `keyDown`).

---

## What this leaves on the table

- D15's `renderCurrentText` save+restore is now a no-op in practice (the suppression guard prevents any scroll that the save+restore would have caught). Left in place as defense-in-depth; remove during the future incremental-render refactor.
- The line-numbers ruler doubling artifact CD captured in screenshots — likely a side effect of the auto-scroll firing mid-render, leaving the ruler view to redraw on a stale clip-view bounds. With Fix A blocking the auto-scroll, the ruler should redraw cleanly. **Verify visually.**
- Incremental rendering (only re-attribute the edited line range) remains the proper long-term fix; would obsolete the suppression guard entirely.

---

## Manual verification needed

CD must visually confirm in real usage:

1. Open a long doc (`docs/roadmap_ref.md`), scroll to middle, type Space and Enter mid-paragraph — viewport should not move and line numbers should redraw cleanly (no doubling).
2. Click a cell in a visible table, type Enter to commit — viewport should not move.
3. Arrow Down/Up at viewport edges — viewport SHOULD follow the caret (regression: navigation must still auto-scroll).
4. `./scripts/md-editor file.md:42` — D9 reveal-at-line should still scroll to line 42 (the suppression guard is keyDown-scoped so external reveal is untouched).

---

## Pivot to TextKit 1 (2026-04-26)

CD-driven decision after D15.1's belt-and-suspenders fixes still didn't fully resolve table-related visual bugs in real-user dogfooding. The pattern is recurring: each scenario we patch reveals another way TK2's lazy-layout interacts badly with our custom-sized `TableRowFragment`. CD's principle: "it's a poor choice to fight a technology 99% of the time." We're fighting.

**Decision**: time-boxed spike on TextKit 1, which has native `NSTextTable` / `NSTextTableBlock` support — the API Apple's own TextEdit falls back to when a table is inserted.

**Spike scope** (D16 / `spikes/d16_textkit1_tables/`):
1. Render `roadmap_ref.md`'s table via native TK1 attributed string with table attributes.
2. Validate four scenarios that defeated TK2:
   - Scroll into a table below initial viewport — does the table render correctly?
   - Click any cell — does the caret land in the cell?
   - Type — does scroll position hold?
   - Wrapped cell — does click-to-line-2 resolve correctly?
3. If all GREEN: plan the migration deliberately. If any fail: continue TK2 with eyes open and document why TK1 wasn't a fit either.

**Code retired by a TK1 switch** (estimated): D8 (table render), D8.1 (reveal mode), D12 (per-cell), D13 (overlay + modal). Kept: D14 (save), workspace shell, command surface, line numbers, scroll-to-line.

**Standard implications**: `engineering-standards_ref.md` § 2.2 prohibits *accidentally* falling into TK1 via `NSTextView.layoutManager` access. A deliberate choice is different — `stack-alternatives.md` will be updated to reflect the new direction if D16 GREEN.

---

## Artifacts that survive the pivot

- `tests/harness/lib.sh`, `tests/harness/test_d15_1_lazy_layout.sh` — harness-driven regression scaffolding; pattern reusable for any future scroll/click scenario.
- `scripts/inspect-editor` — live-state diagnostic that runs against the running app.
- `Sources/Debug/DebugProbe.swift` + View → Show Debug HUD (⌥⌘D) — in-window readout of scrollY, click coords, resolved fragment kind/y, table coords. Critical for diagnosing user-visible bugs that don't repro via harness.
- New harness actions: `synthesize_keypress` (real `NSEvent.keyEvent` through `keyDown`), `set_scroll_via_wheel` (posts the will/didLiveScroll notification chain), `inspect_table_layout`, `inspect_overlay`.

These are infrastructure, not TK2-specific. They carry forward to D16.
