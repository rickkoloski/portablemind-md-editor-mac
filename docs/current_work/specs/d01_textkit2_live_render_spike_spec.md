# D1: TextKit 2 Live-Render Spike — Specification

**Status:** Draft
**Created:** 2026-04-22
**Author:** Rick (CD) + Claude (CC)
**Depends On:** None
**Traces to:** `docs/stack-alternatives.md` (Axis 2 decision, Open Question 6); `docs/vision.md` Principle 1 (Level 1 agent-aware, baseline editing experience)

---

## 1. Problem Statement

The stack committed in `docs/stack-alternatives.md` puts TextKit 2 at the heart of the app — it's the choice that makes the "genuinely native, genuinely live-render" editor possible without the WKWebView compromise we explicitly rejected. That decision has not yet been validated with code. TextKit 2 documentation is thin, real-world Swift samples are thinner, and we don't know in practice how hard it will be to achieve the live-render behaviors our audience needs (type `**foo**`, see **foo**, reveal the `**` when the cursor enters that line).

Before investing in a real Xcode project, an app architecture, a packaging pipeline, or a feature roadmap, we need to answer one question with evidence: **can TextKit 2 actually deliver the live-render editor our vision promises, with effort proportionate to a two-person + AI team?**

This deliverable is a **throwaway spike** — a small, disposable Xcode sample whose value is the write-up, not the code. Its output informs D2 (real project scaffolding) and all subsequent feature specs that touch the editor surface.

---

## 2. Requirements

### Functional — the spike must demonstrate

- [ ] Open a single `.md` file from disk (file picker or drag-drop; either is fine).
- [ ] Display the file with **live-rendered** markdown: at minimum, the following element types render inline without a preview pane:
  - [ ] `# / ## / ### / #### / ##### / ######` headings (progressively smaller, appropriate weight)
  - [ ] `**bold**` and `*italic*` / `_italic_`
  - [ ] `` `inline code` ``
  - [ ] `[link text](url)` links (visually distinct; clickability optional for spike)
  - [ ] Unordered lists (`- `, `* `) and ordered lists (`1. `)
  - [ ] Fenced code blocks ```` ``` ```` with monospace and distinct background
- [ ] **Cursor-on-line reveal** for at least one element (e.g., bold): when the caret enters a line containing `**foo**`, the `**` delimiters become visible; when the caret leaves the line, they collapse back. This is the hardest single behavior in the live-render model and is the litmus test for "TextKit 2 can do this cleanly."
- [ ] Typing produces the expected transform — type `*` `*` `f` `o` `o` `*` `*` and the text renders as **foo** once the second `**` is complete (or once the cursor leaves the line, whichever is easier to implement in the spike).
- [ ] **External-edit reflow:** when the open file is modified on disk by another process (e.g., `echo "# hello" >> file.md`), the buffer updates without losing the caret position on unchanged lines. This is the Level 2 agent-aware baseline.
- [ ] **Undo / redo** works coherently across live-render transforms — undoing a typed bold produces a sane intermediate state, not a visual glitch.

### Functional — explicitly NOT in the spike

- ❌ Formatting toolbar (no buttons, no UI chrome beyond the window and text view)
- ❌ Folder navigation / sidebar / file tree
- ❌ Multiple-document windows or tabs
- ❌ Settings / preferences
- ❌ Submit / handoff primitives
- ❌ Packaging (DMG, notarization, Sparkle)
- ❌ Accessibility polish beyond what TextKit 2 provides by default (but we *do* test VoiceOver — see success criteria)
- ❌ Windows / Linux anything

Discipline: the spike tests the engine, not the product.

### Non-Functional

- [ ] **Performance:** subjective only. Typing feels instant on a 1,000-line markdown file. If it doesn't, that's a finding to report, not a pass/fail.
- [ ] **Effort:** time-boxed at **5 working days** of focused CC-assisted work. If we can't get the required functionality in 5 days, that itself is the answer — we report and decide next steps rather than grinding on.
- [ ] **Code quality:** spike-quality. No tests required. No architecture polish. Cleanup is acceptable loss.

---

## 3. Design

### Approach

Build a single-window macOS app as a new Xcode project named `TextKit2LiveRenderSpike`. The project will live under `apps/md-editor-mac/spikes/d01_textkit2/` and is **not** the real app — it's disposable.

Core architecture for the spike:

1. **`NSTextView` backed by TextKit 2.** Instantiate with `usingTextLayoutManager: true` (the TextKit 2 code path). Host it in SwiftUI via `NSViewRepresentable` so we prove the SwiftUI-plus-AppKit pattern works end-to-end.
2. **Markdown parsing with swift-markdown.** On every text change (or debounced), parse the full buffer into a `Document` AST. swift-markdown is our committed parser, so we validate it as part of the spike.
3. **Live-render via attributed-string application.** Walk the AST and apply `NSAttributedString` attributes (font, foregroundColor, backgroundColor) to the ranges corresponding to rendered elements. For the cursor-on-line reveal, use TextKit 2's viewport and selection APIs to toggle between "show syntax" and "collapse syntax" based on caret position.
4. **File watching with `NSFilePresenter`.** Register the open file; on external change, read and reconcile. Spike-level reconciliation = "reload buffer, preserve caret position if possible" — we don't need a full three-way merge.

We will NOT attempt to hide the delimiter characters in the underlying text storage (that's a common and tempting mistake in live-render editors — it breaks undo, copy/paste, and external-edit reflow). Instead, we toggle their visual rendering (font size, color, or hidden-attribute) while leaving the source characters in the buffer. This is the pattern Obsidian's Live Preview uses and is the most defensible architecturally.

### Key Components

| Component | Purpose |
|---|---|
| `SpikeApp.swift` | SwiftUI `App` entry point; single window scene |
| `EditorContainer.swift` | SwiftUI view hosting the `NSTextView` via `NSViewRepresentable` |
| `LiveRenderTextView.swift` | `NSTextView` subclass or coordinator; owns TextKit 2 setup, parsing hook, attribute application |
| `MarkdownRenderer.swift` | Walks a swift-markdown AST and produces `[NSAttributedString.Attribute]` assignments per range |
| `CursorLineTracker.swift` | Observes selection changes and toggles syntax visibility on the current logical line |
| `FilePresenter.swift` | `NSFilePresenter` conformance + read/reconcile logic |

Spike-level organization, not production architecture. Everything goes in one module.

### Key APIs to exercise

- `NSTextLayoutManager`, `NSTextContentManager`, `NSTextContainer` — the TextKit 2 core trio
- `NSTextView.init(frame:textContainer:)` with `usingTextLayoutManager = true`
- `NSTextContentStorage` / `NSTextParagraph` for content operations
- `NSTextLayoutFragment` and `NSTextViewportLayoutController` for per-viewport rendering
- `swift-markdown`'s `Document.parse(_:)` and the `MarkupVisitor` protocol
- `NSFilePresenter.presentedItemDidChange()` and `NSFileCoordinator` for external-edit handling
- SwiftUI `NSViewRepresentable.makeNSView(context:)` and `updateNSView(_:context:)`

### Out-of-scope mitigation

Where a spike behavior gets hard, **document and move on**. The goal is mapping the territory, not conquering it. If rendering nested lists turns out to be a two-day problem, write down "nested lists are a two-day problem" and skip to the next item. A spike that answers the question "is this hard?" with "yes, here's where specifically" is succeeding.

---

## 4. Success Criteria

The spike is **Complete** when all of the following are true:

- [ ] Sample app builds clean in Xcode against the current Xcode + macOS 14+ SDK.
- [ ] All required functional behaviors from §2 are either demonstrated in the running app or documented as "attempted, here's what we learned."
- [ ] The cursor-on-line reveal (litmus test) works for at least bold, or we have a clear, written explanation of why TextKit 2 makes this harder than expected.
- [ ] External-edit reflow demonstrably works: with the sample app open on a file, running `echo "# test" >> that_file.md` from a terminal causes the editor to update without crashing, losing position, or showing a modal.
- [ ] VoiceOver smoke test: turning on VoiceOver (Cmd+F5) and navigating the editor with the caret reads the text content sensibly (not individual `**` delimiters).
- [ ] A **findings document** is written at `docs/current_work/stepwise_results/d01_textkit2_live_render_spike_COMPLETE.md` that includes:
  - What worked and what didn't
  - APIs that turned out to be essential (link to docs / code references)
  - APIs that turned out to be traps (e.g., "TextKit 1 code paths we accidentally used")
  - Performance observations on a realistic file
  - An **explicit recommendation**: proceed with TextKit 2 (green), proceed with caveats (yellow — list them), or pivot to the WKWebView-embedded editor from stack-alternatives Axis 2 (red — with reasoning)
  - A list of "what to do differently in D2" based on what we learned
- [ ] The spike project is committed to the md-editor-mac repo under `spikes/d01_textkit2/` so future sessions can reference the code even after the conclusion.

A **yellow** outcome is acceptable and expected — TextKit 2 is known to have sharp edges. A **red** outcome would mean reopening stack-alternatives.md Axis 2 before any further architecture work.

---

## 5. Out of Scope

- Production-quality code, architecture, or tests in the spike
- Formatting toolbar and any UI chrome beyond a title-bar and a text view
- Folder browsing, multi-document, tabs
- Packaging, signing, notarization, Sparkle
- The document-type registry abstraction — markdown is hardcoded in the spike
- PortableMind connectivity or any mention of it in the spike UI
- Windows / Linux considerations — the spike is mac-only by definition
- Keyboard-shortcut contract (default NSTextView bindings are fine for the spike)

---

## 6. Open Questions

- [ ] **Minimum macOS version for TextKit 2 affordances we use.** Are we on 13 Ventura or does something force us to 14 Sonoma / 15 Sequoia? Resolve by mid-spike; update `docs/stack-alternatives.md` Open Question 1 with the answer.
- [ ] **How does swift-markdown handle partial or malformed input?** Real editing produces half-typed markdown constantly. Does the parser throw, or does it degrade gracefully? Resolve during first AST integration.
- [ ] **`NSLayoutManager` vs. `NSTextLayoutManager` traps.** Several TextKit 2 samples accidentally fall back to TextKit 1 paths (indicated by `layoutManager` being non-nil on a `NSTextView` we expected to be TextKit-2-only). We need to verify we're actually in the TextKit 2 code path.
- [ ] **Undo coherence with attribute-only changes.** If "hiding" the `**` is done via an attribute rather than a text-storage change, does the native `NSUndoManager` behave as expected, or do we need to suppress attribute-only changes from the undo stack?
- [ ] **Attribute toggling performance on large files.** 10,000-line markdown doc — does caret movement still feel responsive when the "toggle this line's attributes" work runs on every selection change? If not, we need a smarter invalidation strategy.

---

## 7. Definition of Done — the decision gate

D1 is not a shipping feature. Its Done state is a **go / no-go / go-with-caveats decision** for TextKit 2 as the engine. We produce that decision as a written recommendation in the findings document, and D2 starts only after Rick has read the findings and approved the path forward.

The decision, once made, updates `docs/stack-alternatives.md` — either a confirmation note on Axis 2, or a change entry if we pivot.
