# D4: Mutation Primitives + Keyboard Bindings — Specification

**Status:** Complete
**Created:** 2026-04-22
**Completed:** 2026-04-22 — see `docs/current_work/stepwise_results/d04_mutation_primitives_COMPLETE.md`
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D2 (real project + document-type registry + renderer)
**Traces to:** `docs/vision.md` Principle 1 (Level 1 audience — Word/Docs users); `docs/competitive-analysis.md` scoping question Q6 (keyboard contract); `docs/roadmap_ref.md` (D4 = mutations, D5 = toolbar UI); `docs/stack-alternatives.md` architecture lessons #5 (toolbar taxonomy), #6 (keyboard shortcut map)

---

## 1. Problem Statement

D2 established a strong *reading* experience: open a markdown file, see it live-rendered, navigate around it. The corresponding *authoring* story is missing — pressing **Cmd+B** on a selection does nothing; the user cannot make a word bold, a line a heading, or a range a link, except by typing the markdown syntax by hand. For our priority-1 audience (Word/Docs users) that's a deal-breaker: they don't know markdown syntax and don't want to learn it.

D4 introduces **mutation primitives** — pure functions that transform the markdown source in response to a command — and a **command dispatcher** triggered by **Word/Docs-familiar keyboard bindings**. The full set of formatting mutations (bold, italic, inline code, link, heading 0–6, bullet list, numbered list) lands in D4 so that D5 can be a pure UI-wiring deliverable for the visible toolbar.

No visible chrome changes in D4. The user gains formatting power only via keyboard. That's deliberate: it produces a crisp validation gate ("does Cmd+B produce bold?") decoupled from toolbar polish.

---

## 2. Requirements

### Functional — the mutation set

All mutations run against the current selection (and parsed AST) and produce a one-step undo group.

| Mutation | Keyboard | Scope | Toggle? |
|---|---|---|---|
| Bold | **Cmd+B** | selection | yes |
| Italic | **Cmd+I** | selection | yes |
| Inline code | **Cmd+E** | selection | yes |
| Link | **Cmd+K** | selection | yes (if selection is already inside a link, unwrap to plain text; else wrap as `[sel](|)` with caret inside `()`) |
| Body (remove heading) | **Cmd+Opt+0** | line-based | remove heading prefix from each line in selection |
| Heading 1–6 | **Cmd+Opt+1** … **Cmd+Opt+6** | line-based | uniform toggle (see §3) |
| Bullet list | **Cmd+Shift+8** | line-based | uniform toggle |
| Numbered list | **Cmd+Shift+7** | line-based | uniform toggle |

### Functional — semantics

- [ ] **Uniform toggle (line-based).** If every line in the selection is already at the requested state, the command removes it (promotes to body / strips list prefix). Otherwise it applies the state to every line — the "promotion over demotion" rule matching Word, Google Docs, Bear, and Typora.
- [ ] **Uniform toggle (selection-based).** If the selection is fully inside a node of the target type (e.g., selection entirely inside a `Strong`), the command removes the formatting. Otherwise it wraps the selection. Partial overlap (selection starts/ends inside the node) counts as "wrap" for simplicity at D4.
- [ ] **Code-block safety.** If the selection (or caret, for a collapsed selection) intersects any range tagged with our code-block background attribute (the renderer's signal), the command is a **no-op**. No text change, no visible feedback beyond the cursor's natural behavior.
- [ ] **Undo/redo.** Each command is exactly one undo step. Pressing Cmd+Z after a command returns the buffer and selection to their pre-command state.
- [ ] **Selection preservation.** After a command, the caret/selection is placed sensibly:
  - Selection-based wrap: selection spans the original content (now inside the new delimiters).
  - Selection-based unwrap: selection spans the unwrapped content.
  - Link: caret is placed inside the URL brackets `()` with the URL text selected (empty string = zero-length selection inside the parens).
  - Line-based: caret position preserves content-relative offset; if prefix changed by N chars, caret shifts by N.
- [ ] **Live-render refresh.** After a mutation, the editor's rendered view reflects the new source state (same path as textDidChange: re-parse + reapply attributes + collapseAll + updateVisibility).

### Non-functional

- [ ] Standards §1.1 (sandbox-safe) — mutations only modify the in-memory NSTextStorage; no file I/O.
- [ ] Standards §1.2, §1.3 — unchanged from D2.
- [ ] Standards §2.1 — no new interactive NSViews introduced in D4, so no new identifiers. Any later deliverable adding menu items must add identifiers per §2.1.
- [ ] Standards §2.2 — no `.layoutManager` references anywhere.
- [ ] Performance — a single mutation completes (parse → transform → render) within ~50ms on our largest realistic file (`spikes/d01_textkit2/samples/sample-05-large.md`, 284 lines). Subjective smoothness from keypress to rendered result; no Instruments measurement required.

---

## 3. Design

### Key abstractions

```swift
// Shared across primitives — in Sources/Mutations/MutationPrimitive.swift
protocol MutationPrimitive {
    static var identifier: String { get }
    static func apply(to input: MutationInput) -> MutationOutput?
}

struct MutationInput {
    let source: String
    let selection: NSRange
    let document: Document       // pre-parsed swift-markdown AST
}

struct MutationOutput {
    let newSource: String
    let newSelection: NSRange
}
```

Returning `nil` from `apply(to:)` means "no-op" (typically code-block safety triggered). The dispatcher treats nil as: skip text-storage mutation entirely.

### Toggle detection

**Selection-based (Bold, Italic, InlineCode, Link):**
- Pre-parsed AST is searched for nodes of the target type whose range contains the selection range.
- If found → unwrap (compute new source with the wrapping markers removed).
- If not found → wrap (insert markers around the selection).

**Line-based (Heading levels, Bullet, Numbered):**
- Compute the line range of the current selection via `NSString.lineRange(for:)` walking.
- For each line, determine current state from the AST:
  - Line is an H-level N heading? (find Heading node whose source range covers the line)
  - Line is a bullet/numbered list item? (find ListItem node; distinguish Unordered vs. Ordered)
  - Otherwise body text.
- Apply "uniform toggle":
  - All lines already at target → demote to body (or strip list prefix).
  - Otherwise → apply target to all lines, preserving content-only text.

### Code-block safety

The renderer already tags fenced code blocks with `Typography.codeBackground` as the backgroundColor attribute. The mutation dispatcher checks: does any character in the selection range carry that attribute? If yes, return without mutating. Single attribute probe + enumerate, no re-parse needed.

### Command dispatch

```
key press in LiveRenderTextView
        ↓
keyDown(with: NSEvent) — check chord against KeyboardBindings table
        ↓ (if chord matched)
CommandDispatcher.shared.dispatch(identifier: "mutation.bold", in: textView)
        ↓
code-block safety check (attribute probe)
        ↓ (safe)
parse source with swift-markdown
        ↓
MutationResolver.primitive(for: "mutation.bold")
        ↓
primitive.apply(to: input) → MutationOutput?
        ↓ (non-nil)
replace text via NSTextStorage with undo group
        ↓
EditorContainer.Coordinator.renderCurrentText (existing path)
```

The existing `textDidChange` path handles the re-render. The mutation's only job is to produce new source + selection; it registers the change with the NSTextStorage wrapped in an undo group.

### Keyboard bindings

`Sources/Keyboard/KeyboardBindings.swift`:

```swift
enum KeyboardBindings {
    struct Chord: Equatable {
        let modifierFlags: NSEvent.ModifierFlags
        let charactersIgnoringModifiers: String
    }
    struct Binding {
        let chord: Chord
        let commandIdentifier: String
    }
    static let all: [Binding] = [
        Binding(chord: Chord(modifierFlags: [.command], charactersIgnoringModifiers: "b"),
                commandIdentifier: "mutation.bold"),
        // ... one line per chord from the table above
    ]
}
```

`LiveRenderTextView.keyDown(with:)` overrides NSTextView's default, checks the event against `KeyboardBindings.all`, and if a binding matches, dispatches and returns. Otherwise forwards to `super.keyDown(with:)` so regular typing continues to work.

### Module layout additions

```
Sources/Mutations/                 (new — promoted from no-D2-stub)
├── MutationPrimitive.swift        Protocol + I/O types
├── MutationResolver.swift         identifier → primitive lookup
├── CodeBlockSafety.swift          Shared attribute probe
├── BoldMutation.swift
├── ItalicMutation.swift
├── InlineCodeMutation.swift
├── LinkMutation.swift
├── HeadingMutation.swift          Level as parameter; 0 = body
├── BulletListMutation.swift
└── NumberedListMutation.swift

Sources/Keyboard/                  (promoted from stub — D2 had README only)
├── KeyboardBindings.swift         Chord → identifier table
├── CommandDispatcher.swift        Orchestrates parse → apply → text mutation

Sources/Editor/LiveRenderTextView.swift  (modified — add keyDown override)
Sources/Editor/EditorContainer.swift     (modified — wire dispatcher)
```

Stub README under `Sources/Keyboard/` is replaced with Swift code; Sources/Mutations/ is new.

---

## 4. Success Criteria

- [ ] `xcodebuild build` clean, no new warnings.
- [ ] Every mutation in §2's table executes when triggered by its keyboard chord, producing the expected source change and selection state.
- [ ] Uniform-toggle verified for each line-based mutation:
  - [ ] Select 3 body lines, press Cmd+Opt+1 → all 3 become H1
  - [ ] With the 3-H1 selection, press Cmd+Opt+1 again → all 3 become body
  - [ ] Select 3 lines (1 H1 + 2 body), press Cmd+Opt+1 → all 3 become H1 (promotion)
- [ ] Code-block safety verified: place caret inside `sample-04-code.md`'s fenced block, press Cmd+B → no source change.
- [ ] Undo/redo: after any mutation, one Cmd+Z returns the buffer and selection to pre-mutation state; one Cmd+Shift+Z redoes.
- [ ] Selection preservation: after Cmd+B on "foo" selected, `**foo**` is in the source and "foo" (now visually bold) is still selected.
- [ ] Link semantics: Cmd+K with "hello" selected produces `[hello]()` with the caret inside `()`.
- [ ] UITest extended: one new test exercises Bold via simulated keystroke and verifies the text storage's source contains `**` markers around the typed selection.
- [ ] Engineering standards still grep-clean: no `.layoutManager`, all interactive views (there are no new ones in D4) would have identifiers.

---

## 4.5 Validation approach

Same shape as D1 and D2 — Native Phase 1 exploratory demo with a supplemental XCUITest.

**Demo script (keyboard-only; no visual chrome changes):**
1. Open a sample doc. Select a word; Cmd+B. Verify bold renders.
2. Press Cmd+B again. Verify unwraps (source contains no `**` around that word).
3. Select a different word. Cmd+I. Verify italic.
4. Select a whole line. Cmd+Opt+1. Verify H1.
5. Select 3 lines with mixed heading states. Cmd+Opt+2. Verify all H2.
6. Same 3 H2 lines. Cmd+Opt+0. Verify all body.
7. Select 3 body lines. Cmd+Shift+8. Verify bulleted.
8. Same selection. Cmd+Shift+7. Verify numbered.
9. Select text. Cmd+K. Verify `[text](|)` with caret in parens.
10. Position caret inside fenced code block. Cmd+B. Verify **no change**.
11. Undo/redo a few commands. Verify state is coherent.

Evidence: screen recording, transcript, xcodebuild log.

**Automated test:** one new XCUITest case — `testBoldMutationViaKeyboard` — launches the app, types a word, selects it programmatically, simulates Cmd+B, reads the text value, verifies `**word**` is present. Complements the D2 smoke test; both tests live in the same UITests target.

---

## 5. Out of Scope

- **Formatting toolbar UI** — D5. D4's mutations are keyboard-only.
- **NSMenuItem (Format menu) integration** — defer until D5 or later, when we have the UI layer to drive.
- **Tables, images, block quotes, horizontal rules** — later deliverables.
- **Nested lists** — D4 handles flat lists only. Cmd+Shift+8 on an already-bulleted line doesn't produce nested bullets.
- **Checkbox (task) lists** — later.
- **Code-block creation as a mutation** (e.g., Cmd+Shift+K to wrap selection in a fenced block) — later. Note: if we do add this, the code-block-safety rule means we'd need a separate allowed-inside-code-block primitive for fence-toggle.
- **Language-specific transformations inside code** — never at the markdown-editor layer.
- **Smart-paste / markdown-link-from-clipboard** — later.
- **User-configurable keyboard shortcuts** — defer to a preferences deliverable.
- **Mixed-heading-level selection: promote to which level?** — D4 applies the *requested* level to all, per uniform toggle. Anything more sophisticated is a later refinement.

---

## 6. Open Questions

1. **Inline-code shortcut.** Word uses Cmd+E for paragraph-center; Obsidian uses Cmd+E for inline code; Bear uses Cmd+Shift+C; Typora uses Ctrl+Shift+`. D4 recommendation: **Cmd+E** (matches Obsidian, which is the closest peer in our competitive analysis). Decide before implementation.
2. **Link with no selection.** Recommendation: **insert `[](|)` with caret inside `[]`.** Matches Word's Cmd+K behavior (opens a dialog there; we'd instead inline-edit). Alternative: do nothing; require selection.
3. **Heading on an already-list-item line.** Recommendation: **heading replaces the list prefix**, so `- foo` → `# foo` after Cmd+Opt+1. Cleaner user model than nested heading-in-list.
4. **Selection that ends exactly at a newline.** Recommendation: **trim the trailing newline** for selection-based ops, so Cmd+B on "foo\n" produces `**foo**\n` rather than `**foo\n**`.
5. **Code-block safety probe location.** Recommendation: check the START of the selection range. If selection starts outside the block and extends into it, the mutation proceeds on the full selection — which may produce invalid markdown inside the block. Tradeoff: checking every character in the selection is slower but cleaner. D4: start-of-selection check; refine if it produces bad output in the demo script.

---

## 7. Definition of Done

D4 is Complete when:
- All Success Criteria items check.
- Validation demo script (§4.5) executed and captured in `evidence/d04/transcript.md` + screen recording.
- New XCUITest passes via `xcodebuild test`.
- Completion record at `docs/current_work/stepwise_results/d04_mutation_primitives_COMPLETE.md` with per-mutation pass/fail and any new findings.
- Engineering standards §2.1, §2.2 still clean.
- `docs/roadmap_ref.md` updated to mark D4 complete and D5 (toolbar) next.
