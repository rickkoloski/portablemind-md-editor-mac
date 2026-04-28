# D4: Mutation Primitives + Keyboard Bindings — Completion Record

**Status:** Complete
**Created:** 2026-04-22
**Completed:** 2026-04-22
**Spec:** `docs/current_work/specs/d04_mutation_primitives_spec.md`
**Plan:** `docs/current_work/planning/d04_mutation_primitives_plan.md`

---

## 1. TL;DR

**D4 is Complete.** All 13 mutations (Bold, Italic, InlineCode, Link, Body, Heading 1–6, Bullet, Numbered) work end-to-end via their Word/Docs-familiar keyboard chords. Uniform-toggle semantics verified for line-based mutations. Code-block safety holds. Undo/redo coherent. One XCUITest passes via identifier-based queries.

Four findings surfaced during validation — three bugs were fixed in-deliverable, one is a UX-polish item for a later deliverable. All findings are recorded in §3 with their resolutions.

No visible UI chrome changes; D5 (formatting toolbar) is next per `docs/roadmap_ref.md`.

---

## 2. Spec success criteria — pass/fail

| Item | Result |
|---|---|
| `xcodebuild build` clean, no new warnings | ✅ |
| Bold (Cmd+B), Italic (Cmd+I), InlineCode (Cmd+E), Link (Cmd+K) | ✅ all verified |
| Heading 1–6 (Cmd+Opt+1..6), Body (Cmd+Opt+0) | ✅ verified |
| Bullet list (Cmd+Shift+8), Numbered list (Cmd+Shift+7) | ✅ verified (after finding #4 fix) |
| Uniform-toggle (line-based, 3 body → all H2; same H2 → all body) | ✅ verified |
| Code-block safety (Cmd+B inside fenced code → no-op) | ✅ verified |
| Undo/redo (Cmd+Z / Cmd+Shift+Z) coherent | ✅ verified |
| Selection preservation after wrap/unwrap | ✅ |
| Link selection wrap produces `[sel](|)` with caret in parens | ✅ |
| UITest via `xcodebuild test`, identifier-based query | ✅ Bold path verified end-to-end |
| No `.layoutManager` references (§2.2) | ✅ |
| No chord checks outside KeyboardBindings.swift (§2.3) | ✅ |

---

## 3. Findings — all surfaced during validation

### Finding #1 — Untitled/blank buffer didn't live-render (latent D2 bug)

Typing into the blank buffer at app init produced raw markdown (source visible). D2's `EditorContainer.Coordinator.documentType` was nil until a file was opened, and `renderCurrentText` bailed on that nil-guard. No one hit it in D2 because we always opened a file first; D4's Cmd+B exposed it (wrapping worked in source but the renderer didn't fire).

**Resolution:** `documentType` now initializes to `MarkdownDocumentType()` in Coordinator init. Untitled buffers are implicitly markdown (the sensible default for a markdown editor). When a file is opened, `loadFileIfNeeded` reassigns based on extension.

**Severity:** Moderate (broke day-one authoring UX for untitled documents, but opened documents always worked).

### Finding #2 — Strong inside Heading shrank to body-sized bold

Cmd+Opt+1 on a line containing `**bold**` text produced `# **bold**` in source, but the renderer applied `Typography.boldFont` (body-sized) to the Strong range, overwriting the heading's large font. The `#` and plain parts of the heading rendered at H1 size; the bold part shrank to 14pt.

**Resolution:** `RenderVisitor` now tracks `currentHeadingLevel` via enter/exit around `visitHeading`. `visitStrong` and `visitEmphasis` check the current heading level — when > 0, they apply the heading's font (already bold) instead of the body bold/italic. Keeps size correct; deferred the subtle bold+italic trait composition for a later polish deliverable.

**Severity:** Moderate — breaks the visual heading effect whenever inline formatting is present, which is common.

### Finding #3 — Link mutation produces bare `[text]()` (spec-correct, UX-wobbly)

Cmd+K on `asdf` produced `[asdf]()` with caret inside empty parens. Exactly what the spec committed, but the bare empty parens felt abrupt to Rick during demo. Fine for D4 — not a regression.

**Resolution:** Recorded as a **D5+ UX-polish candidate**. Likely approach: pre-fill the parens with placeholder text like `url` and select it so the user types over it. Alternative: pop an inline input field above the caret. Defer.

**Severity:** Informational.

### Finding #4 — Cmd+Shift+7 and Cmd+Shift+8 didn't match (NSEvent Shift semantics)

`KeyboardBindings.match(event:)` used `charactersIgnoringModifiers` to look up the chord key. We assumed that method strips Shift along with Cmd / Opt / Ctrl. **It does not** — it ignores only Cmd, Opt, Ctrl. Shift is still applied. So Cmd+Shift+8 delivered `cim = "*"` (shifted char) rather than `"8"`. Our binding key `"8"` never matched; NSTextView's default fallback handler beeped.

**Diagnosis:** Added temporary NSLog of `modifierFlags`, `characters`, `charactersIgnoringModifiers`, and `keyCode` in `keyDown`. Captured `cim="*" chars="8" keyCode=28` for a Cmd+Shift+8 event. That data was the smoking gun; the fix followed immediately.

**Resolution:** Updated bindings to use the shifted character: `"&"` for Cmd+Shift+7 (numberedList), `"*"` for Cmd+Shift+8 (bulletList). The binding table carries a comment explaining the Shift-still-applied semantic for future readers. Diagnostic logging removed.

**Severity note — i18n caveat:** The shifted-character approach is US-keyboard-specific. On a French AZERTY, Shift+7 is `"7"` (inverted digits/symbols), Shift+8 is `"8"`. Localized keyboard-shortcut support is a candidate for the dedicated i18n pass — likely alongside the D5 toolbar or as a separate future deliverable. The declarative-table rule (`engineering-standards_ref.md` §2.3) keeps that refactor a one-hour change: swap the underlying match strategy in one file, no codebase treasure hunt.

**Severity:** Moderate (D4-blocking in the US layout; latent for any layout).

---

## 4. APIs / patterns that worked

- **swift-markdown's AST lookup for toggle detection.** Finding the enclosing `Strong` / `Emphasis` / `Link` node containing a selection is 15 lines of recursive `walk`. Toggle logic falls out of that one lookup.
- **NSTextView's `shouldChangeText` / `didChangeText` lifecycle for undo integration.** Wrapping the mutation in this sandwich made each command exactly one undo step, with no additional `NSUndoManager` ceremony.
- **Code-block safety via `backgroundColor` attribute probe.** Two-line check, zero additional state. The rendered state already knew "this character is in a code block"; we just asked it.
- **`textDidChange` path as the universal render trigger.** After a mutation replaces the text storage, the existing `Coordinator.textDidChange` path handles re-parse + re-render + cursor-tracker update. Zero new rendering code in D4.

## 5. APIs / patterns that were traps

- **`charactersIgnoringModifiers` doesn't ignore Shift** — documented, but easy to miss. Cost us a diagnostic-logging cycle. Now documented in-code at the binding table.
- **Diagnostic NSLog requires log-stream setup to be useful.** `tmux capture-pane` with narrow width wrapped the KEYDOWN lines unreadably until I widened the pane with `tmux resize-pane -x 200`. Noted as a pane-observability lesson for future sessions.

---

## 6. UITest outcome

Passed. `MutationKeyboardTests.testBoldMutationWrapsSelection` launches the app, types `hello`, Cmd+A, Cmd+B, reads the editor's source via AX value, asserts it contains `**hello**`. Identifier-based query on `md-editor.main-editor` per engineering-standards §2.1.

---

## 7. Engineering standards verification

| Standard | Check | Result |
|---|---|---|
| §1.1 Sandbox-safe source | New files touch only `NSTextStorage` and parsed AST; no file I/O | ✅ |
| §1.2 Bundle ID | Unchanged from D2 | ✅ |
| §1.3 Info.plist | Unchanged from D2 | ✅ |
| §2.1 `accessibilityIdentifier` | No new interactive NSViews in D4, so no new identifiers required | ✅ |
| §2.2 No `.layoutManager` | `rg --type swift 'layoutManager\\b' Sources/` → only comments | ✅ |
| §2.3 Keyboard bindings declarative | All chord checks live in `KeyboardBindings.swift`; grep for `event.charactersIgnoringModifiers` or `event.keyCode` shows only that file | ✅ |

---

## 8. Deviations from spec / plan

- **Diagnostic logging added mid-deliverable** during the finding #4 debug cycle; removed once the bug was understood. Not in the original plan but essential to the diagnosis.
- **Finding #1 (untitled buffer) was not anticipated in the spec** — it's a D2 bug that D4 surfaced. Fixed here rather than filing as a separate deliverable.
- **Finding #2 (Strong-inside-Heading) also not anticipated** — a renderer bug whose visibility depended on a heading mutation being applied. Fixed here since it was discovered while validating the D4 Heading mutation.
- **i18n / non-US-keyboard support** is explicitly a future deliverable per the finding #4 caveat. D4 works on US QWERTY; AZERTY, QWERTZ, and similar layouts need a dedicated pass.

---

## 9. Next

Per `docs/roadmap_ref.md`: **D5 — formatting toolbar** is next. D4's mutations are the underlying primitives; D5 wires them to visible buttons in a SwiftUI toolbar, plus View → Show/Hide Toolbar per vision Principle 1. No new mutation logic in D5 — purely UI composition.

Candidate UX polish from D4 findings to consider absorbing into D5:
- Finding #3 refinement: pre-filled "url" placeholder in Cmd+K / toolbar Link button.
- i18n for keyboard bindings (finding #4 caveat) — may deserve its own deliverable rather than bundling into D5.
