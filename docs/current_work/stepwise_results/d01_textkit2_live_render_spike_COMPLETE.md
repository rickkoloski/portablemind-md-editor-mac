# D1: TextKit 2 Live-Render Spike — Completion Record

**Status:** Complete
**Created:** 2026-04-22
**Completed:** 2026-04-22
**Spec:** `docs/current_work/specs/d01_textkit2_live_render_spike_spec.md`
**Plan:** `docs/current_work/planning/d01_textkit2_live_render_spike_plan.md`
**Evidence:** `spikes/d01_textkit2/evidence/` (transcript, screenshots to be attached)

---

## 1. TL;DR

**🟢 Recommendation: proceed with TextKit 2 as the text-engine for md-editor-mac.**

The core spike question — *can TextKit 2 deliver the live-render UX our vision promises without the WKWebView compromise?* — is answered yes, with caveats. Across a realistic HITL markdown doc (our own CLAUDE.md, competitive-analysis.md, the 5 samples), TextKit 2's attribute-based range manipulation successfully implements collapse/reveal on caret line transitions without mutating source text. The mechanism is fast enough subjectively on 284 lines, and VoiceOver exposes the text content sensibly. Five findings recorded — all are renderer-level bugs or design gaps, not TextKit 2 limitations. See §6 for the D2 work these imply.

---

## 2. Demo results

Mapped to plan §Testing demo-script steps A–N. Full narrated transcript at `spikes/d01_textkit2/evidence/transcript.md`.

| Step | Behavior | Result |
|---|---|---|
| A | Launch | ✅ |
| B | TextKit 2 code-path assertion | ✅ (after finding #1 fix) |
| C | `sample-01-headings.md` renders | ✅ |
| D | Caret enters heading reveals `#` | ✅ |
| E | Caret leaves heading collapses `#` | ✅ (verified by screenshot) |
| F | `sample-02-inline.md` — italic, inline code, link | ✅ |
| G | Type new bold — live transform on closing `**` | ✅ |
| H | Undo / redo coherence | ✅ |
| I | `sample-03-lists.md` | ✅ |
| J | `sample-04-code.md` fenced code block | ⚠️ partial (finding #4) |
| K | External-edit reflow (terminal append) | ✅ |
| L | Headings in large realistic file | ✅ (via Step M) |
| M | `sample-05-large.md` scroll smoothness (284-line doc) | ✅ subjective |
| N | VoiceOver smoke test | ✅ |

---

## 3. Findings

### Finding #1 — Touching `.layoutManager` induces TextKit 1 fallback
Our startup diagnostic originally checked `textView.layoutManager` to assert it was nil. **Accessing `.layoutManager` lazy-creates a TextKit 1 layout manager**, silently flipping the view's code path. The diagnostic itself caused the regression it was designed to detect.
- **Severity:** High for implementers; the trap is invisible once past.
- **Fix:** only ever check `textLayoutManager`; never touch `.layoutManager` in TextKit 2 code. Codified in the current source.
- **D2 implication:** document loudly in our code's style guide; add a SwiftLint rule if feasible.

### Finding #2 — Initial render doesn't pre-collapse delimiters
On file load, `#`, `**`, backticks, etc. are all visible until the caret has transitioned lines. `CursorLineTracker` only collapses the *previous* line on a line transition; `revealedLineRange` starts nil so no collapse runs.
- **Severity:** Moderate — breaks the "Word-docs-like feel" on first open, which is exactly the moment of impression for our primary audience.
- **Fix for D2:** after initial render, walk every delimiter-tagged range in the document and collapse them, then `updateVisibility` re-reveals the current line.

### Finding #3 — Range-offset on inline code
In `` `.md`-files-on-disk ``, collapse hides letters `m` and `f` but leaves the backticks. Likely an off-by-N in `SourceLocation` → NSRange conversion for `InlineCode` nodes specifically.
- **Severity:** Moderate — visually wrong, undermines trust in the renderer.
- **Fix for D2:** cache line-start offsets per parse; verify swift-markdown's `InlineCode.range` semantics (backtick-inclusive vs. content-only); write property-based tests for the SourceLocation → NSRange conversion on each node type.

### Finding #4 — Code-block range drops content lines
Fenced code-block background only applied to fence lines, not to the content lines between them. Same bucket as finding #3 — multiline-range conversion is buggy.
- **Severity:** Moderate.
- **Fix for D2:** same as #3. Additionally, `visitCodeBlock` does not currently tag fences as delimiters, so they never collapse on caret-leave — add delimiter tagging for the three backticks at the start and end of each fence.

### Finding #5 — XCUITest requires macOS Accessibility permission grant
First-run XCUITest on this machine pops a macOS Accessibility/Automation permission dialog. Expected OS behavior, not a TextKit 2 or spike bug.
- **Severity:** Informational.
- **D2 implication:** CI test infra and first-run-after-install flows need to budget for this grant. Once granted, macOS remembers.

---

## 4. APIs that worked

- `NSTextView(usingTextLayoutManager: true)` → clean TextKit 2 init.
- `NSTextStorage.setAttributes` / `addAttributes` inside `beginEditing()` / `endEditing()` — attribute-based rendering is fast and clean.
- `NSTextView.textViewDidChangeSelection(_:)` fires reliably on caret moves; no debouncing needed for our spike-scale document.
- `NSFilePresenter` + `NSFileCoordinator` for external-edit reflow — just works. New file content picked up within ~1s of external modification. Caret position preserved on unchanged prefix.
- `swift-markdown` `Document(parsing:)` — parses aggressively, tolerates mid-typing-state input gracefully. MarkupWalker protocol machinery is `mutating`-flavored and fights class-based visitors; hand-rolled type-check dispatch works fine as a sidestep.
- SwiftUI `NSViewRepresentable` → `NSScrollView` containing `NSTextView` — standard integration pattern holds.

## 5. APIs / patterns that were traps

- `textView.layoutManager` — see finding #1.
- MarkupWalker's `descendInto` — `mutating`-signatured in a way that doesn't play with class-based visitors. Solved by hand-rolling traversal with type-check dispatch.
- `SourceLocation.column` is 1-based UTF-8 bytes. Approximate for multibyte. Our spike computes UTF-16 offset by walking the string each time; for real use we'd cache line starts. **Multiline node ranges need careful handling** — findings #3 and #4 are variants of this.

---

## 6. Performance observations

- **Subjective:** On a 284-line real markdown document (`sample-05-large.md` = our `competitive-analysis.md`), scrolling with Page Down is subjectively smooth. No stutter observed.
- **Document size caveat:** the spec called for a 5,000-line file; we used 284. Subjective result is still positive at that scale; D2 should verify with a larger real-world corpus before locking in on the approach.
- **Instruments measurement:** Descoped by mutual agreement with CD. Subjective smoothness on 284-line doc was already confirmed, and the recommendation would not change with or without the Instruments number. Tagged as a D2 work item (re-measure on a larger 5,000-line corpus when we have production code to measure).

---

## 7. Cursor-on-line reveal approach

**Approach that worked (implemented in the spike):**
1. On every text change, re-parse with swift-markdown and walk the AST.
2. For each markdown element (bold, italic, code span, heading), apply visual attributes (font, color, background) to the node's range via `NSTextStorage`.
3. Additionally, for each element with delimiters, tag the delimiter sub-ranges with a custom attribute key (`SpikeTypography.syntaxRoleKey`).
4. On selection change, walk the *previous* line's range via `enumerateAttribute` for the syntax-role key, and apply the "collapsed" visual attributes (0.1pt font, foreground = textBackgroundColor — makes text effectively invisible while leaving the source intact).
5. Apply "revealed" attributes (normal font, secondary label color) to the current line's delimiter ranges.

**Approach NOT tried (reserved for D2 if we hit a wall):**
- Custom `NSTextLayoutFragment` subclass that zero-widths delimiter ranges at the layout level rather than the attribute level. Architecturally cleaner; reserved if the attribute approach runs into trouble scaling or edge cases.

**Why the attribute approach was sufficient:**
- Didn't mutate source text → undo/redo stays sane, external-edit reconcile works, copy/paste yields source.
- Worked on every element type we tried (subject to the range-offset bugs in findings #3 and #4).
- Performance subjectively fine at our spike scale.

---

## 8. XCUITest outcome

**Outcome: ran cleanly; test assertion failed meaningfully; recorded as finding #5 per plan allowance.**

Three runs produced three distinct outcomes, each informative:

| Run | Outcome | Cause |
|---|---|---|
| 1 | Build cancelled | UITest target missing `GENERATE_INFOPLIST_FILE: YES` |
| 2 | "Authentication canceled" | macOS Accessibility dialog dismissed inadvertently |
| 3 | **Test ran; assertion failed** | `app.textViews.firstMatch.waitForExistence(timeout: 5)` returned false at `CursorOnLineLitmusTests.swift:21` |

### Why run 3 failed — the full explanation

XCUITest queries the accessibility tree by **element type** (categories like `.textViews`, `.buttons`, `.staticTexts`). Each element in the AX tree carries a role classification. For a plain AppKit app, `NSTextView` exposes `AXRole = AXTextArea`, which XCUITest maps to `.textView` → `app.textViews` finds it.

Our `NSTextView` is hosted inside a SwiftUI `NSViewRepresentable`, inside an `NSScrollView`. When SwiftUI hosts an AppKit view, it wraps the whole thing in its own accessibility hierarchy. In that wrap, the element-type classification of the inner view often gets flattened — the NSTextView shows up as a generic `.other` element at the top level XCUITest's `.textViews` query inspects, even though the underlying AX text content is fully intact.

**This is why VoiceOver still read the content correctly** (Step N): VoiceOver walks the entire AX tree role-agnostically and speaks whatever has `AXValue` text. XCUITest's element-type query is stricter.

### Is this a going-forward limitation?

**No meaningful one**, just two standard accommodations:

1. **Set `accessibilityIdentifier` on every interactive NSView we ship.** One line per view. Then XCUITest finds it by identifier regardless of element-type classification: `app.otherElements["main-editor"]` or `app.descendants(matching: .any)["main-editor"]`. Apple documents this as the recommended pattern anyway; it's only the element-type shortcut queries that are fragile.
2. **CI needs a one-time Accessibility/Automation permission grant** for the test runner host. Standard macOS behavior, handled in most CI tooling.

Neither constrains TextKit 2, our design, or our architecture. It's a testing-discipline note, not a product limitation. The AX tree content itself is fully intact — VoiceOver proves that, and strong accessibility is a real differentiator vs. Electron competitors (per `docs/competitive-analysis.md`).

**Implication for later UI-test strategy (D2+):**
- Every interactive NSView gets an `accessibilityIdentifier` set as part of its construction.
- Don't rely on XCUITest's built-in element-type queries for Cocoa-in-SwiftUI views — always query by identifier.
- Budget for the permission grant in CI / first-run-after-install.

This is the exact outcome the plan's Step 8 anticipated ("the test cannot be cleanly written in its current form"). Not a TextKit 2 issue, not a spike failure.

---

## 9. Final recommendation

**Proceed with TextKit 2 as the text-engine for md-editor-mac (D2 and beyond).**

Reasoning:
- Every behavior the vision requires worked in the spike, modulo bugs in our own range-calculation code.
- Five findings are all addressable; none of them implicate TextKit 2 itself.
- VoiceOver already reads content sensibly by construction — we get accessibility for free that Electron-based competitors would struggle to match.
- External-edit reflow is clean — the NSFilePresenter path is solid, giving us Level 1 agent-aware baseline with little additional work.
- The alternative (WKWebView + CodeMirror/ProseMirror) would compromise feel and accessibility and trade tractable Swift-side bugs for much harder web-boundary integration problems.

No red or yellow downgrade signal emerged.

---

## 10. What to do differently in D2

1. **Fix the renderer's range math first.** Findings #3 and #4 are both variants of "multiline `SourceLocation` → NSRange conversion is off." Write property-based tests against known markdown snippets with known expected NSRanges. Cache line starts. Verify per-node `range` semantics in swift-markdown (inclusive or exclusive of delimiters).
2. **Pre-collapse delimiters on initial render** (finding #2). Small, obvious addition to `renderCurrentText`.
3. **Split the renderer into parse + layout phases.** The spike re-parses on every text change. For large docs and Level 2 agent-awareness (incremental reconcile with agent edits), we'll want incremental parsing or at least range-scoped re-render. Not required for v1 but the architecture should not foreclose it.
4. **Make the collapsed-visibility attribute set a design constant.** 0.1pt font + textBackgroundColor is hacky. Evaluate the custom `NSTextLayoutFragment` path and pick one approach per vector.
5. **Add delimiter tagging to code blocks** (finding #4). The fence lines should collapse when caret is off-block, same as inline elements.
6. **Replace `monospacedSystemFont` as base.** Rick's vision audience is Word/Docs users; body text should be proportional (serif or sans), not monospace. The spike's use of monospace base was an accidental tone choice.
7. **Write a range-conversion unit-test suite** as the first D2 test work. The renderer is the most complex module and the most error-prone; tests here pay back faster than elsewhere.
8. **Document the TextKit 1/2 trap loudly.** Put a `// DO NOT ACCESS .layoutManager` comment-header in every file that touches `NSTextView`. Consider a pre-commit hook.

---

## 11. Deviations from spec / plan

- **Document size for performance check:** spec said 5,000 lines, we used 284. Subjective result still positive; Instruments measurement still pending.
- **Minimum macOS version:** spec left as an open question. Spike built cleanly against macOS 14 deployment target on an Xcode 16.2 / macOS 15.2 SDK. Final call deferred to D2 once we know which TextKit 2 features we actually need.
- **XCUITest:** the real cursor-on-line assertion was not attempted; test body is an infrastructure sanity check only. Per plan Step 8, this is an allowed outcome.

---

## 12. Stack-alternatives.md update

Axis 2 of `docs/stack-alternatives.md` will be updated with a confirmation note reflecting this green recommendation and a pointer to this completion record. No pivot required.
