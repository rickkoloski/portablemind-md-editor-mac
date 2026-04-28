# D9: Scroll-to-Line on Open — COMPLETE

**Shipped:** 2026-04-23
**Spec:** `docs/current_work/specs/d09_scroll_to_line_spec.md`
**Promoted from:** Harmoniq task #1367 in portablemind project #53

---

## What shipped

`md-editor://open?path=...&line=N[&column=M]` places the caret at (line, column), 1-based, and scrolls to make it visible. Works on both a freshly-opened tab and an already-open tab.

CLI suffix: `./scripts/md-editor path.md:42` and `./scripts/md-editor path.md:42:10`. No suffix = D6 behavior (no regression).

Dogfood validated: CD ran `./scripts/md-editor docs/roadmap_ref.md:30` and confirmed the view landed ~30 lines in (line-number absence noted as a separate polish item — backlogged as Harmoniq task #1379).

---

## Files created / modified

| File | Action |
|---|---|
| `Sources/CommandSurface/EditorFocusTarget.swift` | Create |
| `Sources/Support/StringLineLocation.swift` | Create |
| `Sources/Workspace/EditorDocument.swift` | Modify — add `@Published var pendingFocusTarget: EditorFocusTarget?` |
| `Sources/CommandSurface/OpenFileCommand.swift` | Modify — parse line/column, set on doc after `tabs.open` |
| `Sources/Editor/EditorContainer.swift` | Modify — Coordinator subscribes to `$pendingFocusTarget`, applies after window-attach |
| `scripts/md-editor` | Modify — suffix parsing for `:line` and `:line:column` |
| `docs/roadmap_ref.md` | Modify — D9 entry ✅ |

---

## Findings

**#1 — TextKit 2 `scrollRangeToVisible` silently no-ops before the text view is attached to a window.** First impl called `scrollRangeToVisible` inside a single `DispatchQueue.main.async` hop after the `$pendingFocusTarget` sink fired. Log output confirmed the apply ran with a correct NSRange location, but the view stayed at line 1. Root cause: on the first runloop tick after `makeNSView`, the text view exists but `textView.window` is still `nil` — scrolling without geometry is a silent no-op on TextKit 2.

Fix: `scheduleApply(_:attempt:)` defers the apply until `textView.window != nil`, with a bounded retry loop (~30 × 16ms ≈ 0.5s ceiling) for the initial window-attach race. Once attached, calls `textLayoutManager.ensureLayout(for: textContentManager.documentRange)` — explicit TextKit 2 layout pass — then performs the `setSelectedRange` + `scrollRangeToVisible`. Standards §2.2 preserved: no `.layoutManager` access; `textLayoutManager` and `NSTextLayoutManager.ensureLayout` are the TextKit 2 APIs.

**#2 — `@Published` replays current value on subscribe.** This is the intended behavior and the reason the subscription does **not** use `.dropFirst()` (unlike the sibling `$source` subscription). If OpenFileCommand sets `pendingFocusTarget` before the Container is built (the usual case when the CLI opens a not-yet-open file), the target value is already present by the time the Coordinator subscribes, and `@Published`'s replay-on-subscribe delivers it immediately.

**#3 — "Publishing changes from within view updates" SwiftUI warning.** Clearing `pendingFocusTarget = nil` inside the sink triggered SwiftUI's "publishing changes from within view updates is not allowed" runtime fault (fired ~6 times per invocation). Fixed by hopping the clear to another `DispatchQueue.main.async` so it runs strictly after the current view update pass.

**#4 — CLI suffix parsing preserves literal-colon file paths.** The shell wrapper only strips a `:line` or `:line:col` suffix when the literal path doesn't exist and the stripped form does. Files whose names contain real colons (rare on macOS — Finder shows `:` as `/`, but allowed) still work. Opted to keep this as a polite fallback rather than require a flag.

---

## Deviations from spec

- Spec §3 suggested `DispatchQueue.main.async` as a single-hop mitigation. Implementation needed a retry loop until window-attach, plus an explicit `ensureLayout` call and a second hop to clear the pending target. All consistent with the spec's intent; the implementation details are richer. Finding #1 captures why.

---

## Backlogged from this deliverable

- **Line numbers (toggleable gutter)** — CD's observation during dogfood: scroll-to-line was hard to visually verify without line numbers in the editor. Captured as Harmoniq task #1379 under the D6 polish backlog.
- **Selection-range variant** — already in the backlog as #1368 "Text selection on open". Reuses the `EditorFocusTarget` enum (adds a `.selection(...)` case), the `pendingFocusTarget` plumbing, and the CLI suffix parser. Small delta when promoted.

---

## Verification

- Build green after all changes.
- No new `.layoutManager` references (§2.2 preserved).
- Dogfooded:
  - `./scripts/md-editor docs/roadmap_ref.md:30` → landed ~line 30.
  - `./scripts/md-editor README.md:40:5` → landed mid-document.
  - `./scripts/md-editor CLAUDE.md` (no suffix) → top of file, no regression.
- D1–D6 behavior unchanged (existing tabs, existing open, existing folder-open all work as before).
