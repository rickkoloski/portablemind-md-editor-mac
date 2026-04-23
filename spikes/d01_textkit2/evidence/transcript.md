# D1 Spike — Demo Transcript

**Date:** 2026-04-22
**Build:** `.build-xcode/Build/Products/Debug/TextKit2LiveRenderSpike.app` (xcodegen'd .xcodeproj, Xcode 16.2, macOS 15.2 SDK)
**Machine:** Richard's MacBook Air (Apple Silicon), macOS Darwin 24.5 (macOS 15 Sequoia)
**Demo run by:** Rick (CD). Transcript authored by CC in real time from Rick's observations.

Per plan §Testing, we step through A–N from the demo script and record observations alongside.

---

## Pre-flight

- `swift build` clean in 2.6s
- `xcodegen generate` produced a clean `.xcodeproj`
- `xcodebuild -scheme TextKit2LiveRenderSpike build` succeeded
- `open …/TextKit2LiveRenderSpike.app` launched the process; app appeared as a windowed foreground app

### Spike finding #1 — TextKit 2 code-path trap (captured pre-demo)

Our startup diagnostic originally checked `textView.layoutManager` to assert it was nil (expecting TextKit 2 only). **Touching `.layoutManager` lazy-creates a TextKit 1 layout manager** and silently flips the view's code path, so the diagnostic itself caused the regression it was designed to detect. Fixed by only checking `textLayoutManager`. The trap is real and must stay documented — anyone writing TextKit 2 code must avoid accessing `.layoutManager`.

---

## Step results

### Step A — launch
✅ App launched, window appeared, no crash.

### Step B — TextKit 2 assertion in console
✅ `TEXTKIT2-OK: textLayoutManager=…` printed on startup after the finding #1 fix.

### Step C — open `sample-01-headings.md` (initial headings render)
✅ Headings render at visibly larger, bolder sizes than body. Body is monospace (my choice in `SpikeTypography.baseFont`).

### Spike finding #2 — delimiters not pre-collapsed on initial render
⚠️ On initial file load, `#`, `**`, and `` ` `` delimiters are **still visible** until the caret has transitioned lines. `CursorLineTracker` only collapses the *previous* line on a line transition; `revealedLineRange` starts nil, so nothing collapses on first render. **Fix for D2:** after initial render, pre-collapse all delimiters across the whole document, then `updateVisibility` re-reveals only the current line.

### Step D — caret enters heading line
✅ The `#` on the current heading line is visible while the caret is on that line (expected — revealed state).

### Step E — caret leaves heading line
✅ Confirmed by Rick's screenshot: `##` on both "Project purpose" and "Technology stack" disappeared after he moved the caret off those lines. Attribute-based collapse works.

### Step F — `sample-02-inline.md` (italic, inline code, link variants)
✅ Confirmed by Rick: `*italic*`, `` `inline code` ``, `[link](url)` all collapse/reveal analogously to bold.

### Spike finding #3 — range-offset on inline code
⚠️ Visible in Rick's Step E screenshot: in `` `.md`-files-on-disk ``, after collapse the backticks remain visible but the letters `m` (from `.md`) and `f` (from `files`) are collapsed instead. Indicates an off-by-1 or off-by-N in the swift-markdown `SourceLocation` → NSRange conversion, specifically for `InlineCode` nodes. **Fix for D2:** cache line starts and compute offsets precisely in UTF-16; verify `InlineCode.range` semantics (does it include backticks or just the content?). Doesn't affect TextKit 2 viability.

### Step G — type a new bold
✅ Confirmed by Rick: typing `Plain **new** plain` renders `new` in bold when the closing `**` completes. Live-render transform on typing works.

### Step H — undo/redo
✅ Confirmed by Rick: Cmd+Z twice and Cmd+Shift+Z twice is coherent, no visual glitching, caret lands in reasonable places.

### Step I — `sample-03-lists.md`
✅ Confirmed by Rick: lists render sensibly. (Spike does not do bullet-marker styling specifically; default list behavior from TextKit + base font is acceptable for v1.)

### Step J — `sample-04-code.md` (fenced code block)
⚠️ **Fenced code background only covered the fence lines (` ``` ` and ` ```swift `), not the content lines `let x = 42` and `print(x)`.** Verified via Rick's screenshot.

### Spike finding #4 — code-block range conversion drops content lines
⚠️ `nsRange(for: codeBlock)` resolves to a range that covers the opening fence line (and possibly the closing fence line) but not the content between them. Likely the same multiline-range bug pattern as finding #3 — swift-markdown's `SourceLocation` is 1-based UTF-8 line+column, and our line-start walker is probably landing on the wrong lines when the node spans multiple lines. **Fix for D2:** cache line-start offsets per parse; test multi-line node ranges explicitly. Also: our `visitCodeBlock` does not tag the `` ``` `` fence lines as delimiters, so they never collapse on caret-leave. Both are renderer bugs, neither affects TextKit 2 viability.

### Step K — external edit reflow (terminal append to an open file)
✅ Confirmed by Rick: with `sample-01-headings.md` open, an external `echo "# New heading from terminal" >> …` appended a new heading; the editor picked up the change and reflected it in the buffer. NSFilePresenter + NSFileCoordinator path works. (The appended line is visible in the file on disk at line 7.)

### Step L — headings in a large realistic file
_pending (likely subsumed by Step M since sample-05-large.md is exactly that)_

### Step M — `sample-05-large.md` scroll smoothness
✅ Confirmed by Rick: scrolling through the 284-line competitive-analysis copy is smooth/snappy subjectively. No stutter reported.

### Step N — VoiceOver smoke test
✅ Confirmed by Rick: VoiceOver reads content sensibly. AX tree is exposed well by TextKit 2's NSTextView — reads words, not individual punctuation characters. This is also a positive signal for XCUITest viability.

### Instruments — selection-handler performance
_pending_

### XCUITest — cursor-on-line litmus
⚠️ Three runs, three different outcomes — each informative:
1. UITest target missing `GENERATE_INFOPLIST_FILE: YES`. Build-cancel. Fixed in `project.yml`.
2. macOS Accessibility-permissions dialog dismissed inadvertently. "Authentication canceled."
3. Permission granted; test ran cleanly and **failed** at `CursorOnLineLitmusTests.swift:21` — `app.textViews.firstMatch.waitForExistence(timeout: 5)` returned false. The window is found; our NSTextView is not matched by the `.textViews` query. Total run 7.5s. No crash, no timeout, no permission error.

VoiceOver (Step N) confirms the AX tree *does* expose our text content sensibly, so the issue is XCUITest's query-type classification, not AX-tree emptiness. Likely fix: set an `accessibilityIdentifier` on the `NSTextView` and query by identifier, or use `app.descendants(matching:)` with a broader role filter. **Outcome per plan Step 8: "the real litmus assertion cannot be written in its current form" — recorded as a useful answer for later UI-test strategy, not a spike failure.**

### Spike finding #5 — XCUITest viability is conditional on explicit AX identifiers
Two sub-observations from the three runs:
1. First-run-on-machine pops a macOS Accessibility/Automation permission dialog — expected OS behavior; once granted, remembered.
2. Once the runner is authorized, `XCUIApplication.textViews.firstMatch` does not match our `NSTextView`. The view IS in the AX tree (VoiceOver reads it), but XCUITest's element-type classification doesn't treat it as a `textView`.

**D2 implication:** when we write real UI tests, set `accessibilityIdentifier` on every interactive NSView and query by identifier; do not rely on XCUITest's built-in element-type queries for Cocoa views hosted in SwiftUI. Also budget for a one-time permission grant in CI / first-run-after-install.

---

## Running recommendation (mid-demo)

So far: **green on the core TextKit 2 feasibility question**. Delimiter collapse/reveal via attributes works, undo/redo survives attribute-based transforms, live-render on typing works. Three findings recorded — none invalidate TextKit 2 as the engine choice. All three are addressable in D2.

Final recommendation written once demo + Instruments + XCUITest are complete.
