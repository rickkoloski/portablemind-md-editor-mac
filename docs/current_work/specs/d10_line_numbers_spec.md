# D10: Toggleable Line Numbers — Specification

**Status:** Draft
**Created:** 2026-04-23
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D2 (EditorContainer / LiveRenderTextView), D5 (View menu toggle pattern)
**Traces to:** `docs/engineering-standards_ref.md` §2.2 (no `.layoutManager`). Surfaced during D9 dogfood — scroll-to-line validation was gated on visible line numbers. Promoted from Harmoniq task #1379.

---

## 1. Problem Statement

Line numbers are currently absent. D9 scroll-to-line works but is hard to visually verify (CD: "it definitely wasn't on the top and it looked like about 30 lines"). D8 table rendering validation will have the same gap. Beyond dogfood, line numbers are a standard markdown/code-editor affordance for collaborative review ("check line 42").

---

## 2. Requirements

### Functional

- [ ] Left gutter alongside the editor shows line numbers, one per logical (source) line. Wrapped visual lines show the gutter number only on the first line fragment.
- [ ] Gutter visibility toggled by **View → Show Line Numbers** / **View → Hide Line Numbers** menu item. Keyboard shortcut `Cmd+Option+L`.
- [ ] Default: **off** (keeps the Word/Docs-familiar default per vision Principle 1, audience-1).
- [ ] State persists across relaunch via `@AppStorage` — same mechanism as toolbar and sidebar visibility.
- [ ] Line numbers update as text is edited (newlines added/removed shift subsequent numbers immediately).
- [ ] Gutter has a monospaced digit font so number widths don't jitter as counts roll from 9→10, 99→100, etc.

### Non-functional

- [ ] Standards §2.1 — View menu item gets an `accessibilityIdentifier` from the central enum.
- [ ] Standards §2.2 — TextKit 2 only. Use `NSTextLayoutManager.enumerateTextLayoutFragments` for line-fragment geometry. No `.layoutManager` access.
- [ ] Standards §2.3 — the new `Cmd+Option+L` shortcut is declared on the menu item (per the menu-chord carve-out).
- [ ] Gutter must not scroll lag — drawing is O(visible fragments), not O(document).

### Out of scope

- Clickable line numbers (backlogged as polish).
- Current-line highlight in the gutter (backlogged as polish).
- CLI / URL-scheme control of visibility — that's Harmoniq task #1380, a follow-on.

---

## 3. Design

### NSRulerView over custom overlay

TextKit 2's scroll view cooperates natively with `NSRulerView` — `NSScrollView.verticalRulerView`. Custom `NSRulerView` subclass does the drawing in its `drawHashMarksAndLabels(in:)`. Tracks the NSTextView via `clientView`.

### Line-start index cache

Recompute `[Int]` of character offsets for the start of each line when the source string changes. Binary-search during draw to map a fragment's starting offset to a line number.

### Draw loop

`NSTextLayoutManager.enumerateTextLayoutFragments(from: documentRange.location, options: .ensuresLayout)` yields fragments in document order. For each:
- Compute frame in ruler-view coordinates.
- Skip if above dirty rect; stop iterating once past dirty rect.
- Line number from the fragment's element-range start offset via the cached index.
- Draw right-aligned monospaced digits.

### Toggle plumbing

- `AppSettings.lineNumbersVisible: Bool` (@AppStorage, default false).
- EditorContainer gains `@ObservedObject var settings: AppSettings = .shared`.
- `updateNSView` syncs the ruler attach state to `settings.lineNumbersVisible`.
- View menu entry added to the existing `CommandGroup(replacing: .toolbar)` neighborhood in MdEditorApp.

---

## 4. Success Criteria

- [ ] Line numbers off by default on fresh launch.
- [ ] `View → Show Line Numbers` reveals the gutter; `Cmd+Option+L` toggles.
- [ ] Open `README.md` with line numbers on; scroll; gutter stays aligned with text lines and digits don't jitter.
- [ ] Open a document, edit it (add/remove lines), gutter updates.
- [ ] Relaunch — line-number state persists.
- [ ] No `.layoutManager` references added (grep).
- [ ] No regression on D1–D9 (existing tabs, scroll-to-line, etc.).

---

## 5. Implementation Steps

1. `AppSettings.swift` — add `@AppStorage("lineNumbersVisible") var lineNumbersVisible: Bool = false`.
2. `AccessibilityIdentifiers.swift` — add `viewMenuToggleLineNumbers`.
3. `Sources/Editor/LineNumberRulerView.swift` (new) — NSRulerView subclass with the line-start cache and TextKit 2 fragment enumeration.
4. `Sources/Editor/EditorContainer.swift` — observe AppSettings, install/remove the ruler in `updateNSView`, invalidate the cache on text change.
5. `Sources/App/MdEditorApp.swift` — View menu entry with `Cmd+Option+L`.
6. Build, launch, dogfood: turn on/off, scroll, edit, relaunch.
7. `d10_line_numbers_COMPLETE.md`, roadmap update.
8. Commit + push.
