# D9: Scroll-to-Line on Open — Specification

**Status:** Draft
**Created:** 2026-04-23
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D6 (CommandSurface + TabStore + EditorContainer)
**Traces to:** `docs/engineering-standards_ref.md` §2.2 (no `.layoutManager`), §2.4 (CommandSurface declarative). Promoted from Harmoniq task #1367 in portablemind project #53.

---

## 1. Problem Statement

Workflow today: CC writes a spec with an embedded questions-and-clarifications table. CD opens the spec and has to manually scroll to the questions. At ~300-line specs this is real friction, and the friction compounds per review cycle.

D9 adds one capability: the CLI and URL scheme can request "open this file and land the caret on line N." Uses the existing D6 `open` command — new `line`/`column` params, no new command identifier.

---

## 2. Requirements

### Functional

- [ ] `md-editor://open?path=...&line=N` places the caret at the start of line N (1-based), scrolls to make it visible.
- [ ] `md-editor://open?path=...&line=N&column=M` places the caret at (line N, column M), both 1-based.
- [ ] Out-of-range line clamps to the last line. Out-of-range column clamps to end-of-line.
- [ ] Works whether the file is a fresh open or an already-open tab (in the latter case, the caret moves without re-reading the file).
- [ ] CLI shell wrapper accepts `./scripts/md-editor path.md:42` and `:42:10` suffix notation. Suffix is stripped from the path, converted into `&line=...&column=...` query params.
- [ ] No suffix = today's behavior (no change).
- [ ] Composes with `tab=new` — `&tab=new&line=42` forces a new tab and scrolls to the line.

### Non-functional

- [ ] Standards §2.2 — no new `.layoutManager` references. Scrolling goes through TextKit 2 (`scrollRangeToVisible` on NSTextView is fine; internally routes through the text layout manager).
- [ ] Standards §2.4 — the extension stays inside `Sources/CommandSurface/` and the `OpenFileCommand` handler. No scattered scroll-handling code.
- [ ] No new accessibility identifiers — scroll isn't a new interactive view.
- [ ] No new keyboard shortcuts.

---

## 3. Design

### EditorFocusTarget

New type in `Sources/CommandSurface/` (future-proofs #1368 text selection as a case variant):

```swift
enum EditorFocusTarget: Equatable {
    case caret(line: Int, column: Int)
    // Future: case selection(startLine, startColumn, endLine, endColumn)
}
```

### EditorDocument gains a pending-focus-target slot

```swift
@Published var pendingFocusTarget: EditorFocusTarget? = nil
```

Set by `OpenFileCommand` after `tabs.open(...)`; consumed (and cleared) by `EditorContainer.Coordinator`.

### OpenFileCommand parses line/column

Parse `line` / `column` params. If present, set `doc.pendingFocusTarget = .caret(line, col)` after the open call. If absent, behavior is unchanged.

### EditorContainer applies the target

Coordinator subscribes to `document.$pendingFocusTarget` (no `dropFirst` — we want the current value on connect). When non-nil:

1. Convert `(line, column)` to an `NSRange` location via a small `String.nsLocation(forLine:column:)` helper.
2. Call `textView.setSelectedRange(NSRange(location:..., length: 0))`.
3. Call `textView.scrollRangeToVisible(...)`.
4. Clear `document.pendingFocusTarget = nil`.

Layout-timing question: on a fresh open, the text view is seeded in `makeNSView` but layout may not be complete when the target arrives. Mitigation: wrap the apply in `DispatchQueue.main.async` so it runs after the current runloop tick — the initial layout completes first. If that still flickers, fall back to the NSView's `viewDidMoveToWindow` lifecycle.

### Line/column conversion helper

`String.nsLocation(forLine:column:)` — scan NSString for newlines, 1-based. Clamp line to last, column to end-of-line. Return 0-based NSRange location.

### Shell wrapper suffix parser

Parse `path.md:42` or `path.md:42:10` by stripping a trailing `:<digits>(:<digits>)?` from the argument. Build `&line=42&column=10` (or just `&line=42`) into the URL. If the file exists at the literal path including the colon (rare; macOS allows `:` in filenames), the strip would misbehave — check file existence before stripping.

---

## 4. Success Criteria

- [ ] `./scripts/md-editor docs/roadmap_ref.md:30` opens the file (or focuses its tab) and lands the caret on line 30, visible.
- [ ] `./scripts/md-editor docs/roadmap_ref.md:5:3` lands on line 5, column 3.
- [ ] Path without suffix opens as today (no regression).
- [ ] `md-editor://open?path=...&tab=new&line=10` forces a new tab and lands on line 10.
- [ ] Existing D1-D6 tests still pass; `grep -r '\.layoutManager' Sources/` returns no new hits.
- [ ] Dogfood: CD demos by opening a section of `README.md` via the CLI suffix.

---

## 5. Out of Scope

- Selection ranges (`&select=42-44`) — deferred to #1368 as a follow-on D deliverable.
- `&select` or range-open variants.
- Telling the user "line clamped to last line" when they overshoot — silent clamp.
- `path:42` files where the colon is a real character.

---

## 6. Implementation Plan (compressed)

1. `Sources/CommandSurface/EditorFocusTarget.swift` (new) — the enum.
2. `Sources/Workspace/EditorDocument.swift` — add `@Published var pendingFocusTarget: EditorFocusTarget?`.
3. `Sources/CommandSurface/OpenFileCommand.swift` — parse line/column, set on the doc after `tabs.open`.
4. `Sources/Support/StringLineLocation.swift` (new) — `String.nsLocation(forLine:column:)` helper.
5. `Sources/Editor/EditorContainer.swift` — Coordinator subscribes to `document.$pendingFocusTarget`, applies on non-nil.
6. `scripts/md-editor` — parse `:line(:col)?` suffix, append to URL.
7. Build, launch, dogfood with `./scripts/md-editor docs/roadmap_ref.md:30` and `:5:3`.
8. Write `docs/current_work/stepwise_results/d09_scroll_to_line_COMPLETE.md`.
9. Update `docs/roadmap_ref.md` — mark D9 shipped.
10. Commit + push.
