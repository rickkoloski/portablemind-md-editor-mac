# D1: TextKit 2 Live-Render Spike — Implementation Instructions

**Spec:** `d01_textkit2_live_render_spike_spec.md`
**Created:** 2026-04-22

---

## Overview

Build a throwaway macOS Xcode sample app that validates TextKit 2's ability to deliver the live-render markdown UX described in `docs/vision.md` Principle 1 and committed in `docs/stack-alternatives.md` Axis 2. Output a green/yellow/red recommendation on TextKit 2 for the real app.

---

## Prerequisites

- [ ] Xcode 15.x or later installed
- [ ] macOS 14 Sonoma or later on the dev machine (to access current TextKit 2 APIs; minimum-deployment-version decision is one of the spike's outputs)
- [ ] Apple Developer account signed into Xcode (for running on the local mac — no distribution profile needed for a spike)
- [ ] Git branch or subdirectory prepared — use `apps/md-editor-mac/spikes/d01_textkit2/` with an `.xcodeproj` inside
- [ ] swift-markdown dependency identified — `https://github.com/swiftlang/swift-markdown` — added via Swift Package Manager inside Xcode

---

## Implementation Steps

### Step 1: Create the Xcode project

**Files:** `apps/md-editor-mac/spikes/d01_textkit2/TextKit2LiveRenderSpike.xcodeproj`

- Xcode → File → New → Project → macOS → App
- Product name: `TextKit2LiveRenderSpike`
- Interface: **SwiftUI**
- Language: **Swift**
- Bundle identifier: `ai.portablemind.md-editor.spike.d01`
- Save into `apps/md-editor-mac/spikes/d01_textkit2/`
- Do NOT enable Core Data, CloudKit, or Include Tests (we'll add one UI test manually in Step 7)
- Open the scheme and set macOS Deployment Target to **14.0** initially; we'll revisit and record the final answer in the findings doc

### Step 2: Add swift-markdown dependency

**Files:** project `Package.resolved`

- Xcode → File → Add Package Dependencies
- URL: `https://github.com/swiftlang/swift-markdown`
- Dependency rule: Up to next major (from 0.3.0 or current stable)
- Add to the main app target

Verify the import works by adding `import Markdown` to `ContentView.swift` and building clean.

### Step 3: Build the SwiftUI shell

**Files:** `SpikeApp.swift`, `EditorContainer.swift`

```swift
// SpikeApp.swift — replace the scaffolded ContentView wiring
@main
struct TextKit2LiveRenderSpikeApp: App {
    @State private var fileURL: URL?

    var body: some Scene {
        WindowGroup {
            EditorContainer(fileURL: $fileURL)
                .frame(minWidth: 700, minHeight: 500)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Open…") { openFile() }
                    }
                }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { fileURL = panel.url }
    }
}
```

`EditorContainer` is the SwiftUI → AppKit bridge; defer its implementation until Step 4.

### Step 4: Implement the TextKit 2 editor view

**Files:** `EditorContainer.swift`, `LiveRenderTextView.swift`

Implement `EditorContainer` as `NSViewRepresentable` wrapping an `NSScrollView` containing an `NSTextView` configured for TextKit 2:

```swift
func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true

    let textView = NSTextView(usingTextLayoutManager: true)  // TextKit 2
    textView.isEditable = true
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    textView.delegate = context.coordinator

    scroll.documentView = textView
    return scroll
}
```

**Critical verification** — assert that `textView.textLayoutManager != nil` and `textView.layoutManager == nil`. If both are non-nil, you are accidentally in the TextKit 1 code path; fix before proceeding. Log both values on startup.

`LiveRenderTextView.swift` can start as a reference to the `NSTextView` held in the Coordinator. Put the parse + render logic in Step 5.

### Step 5: Parse markdown and apply attributes

**Files:** `MarkdownRenderer.swift`, `LiveRenderTextView.swift` (delegate extension)

On every `textDidChange(_:)` (consider debouncing with a 50ms delay only if typing latency shows it's needed):

1. Read the full text from `textView.string`
2. Parse with `Document(parsing: text)` from swift-markdown
3. Walk the AST with a custom `MarkupVisitor` that collects `(NSRange, [NSAttributedString.Key: Any])` pairs
4. Apply attributes via `textView.textStorage?.setAttributes(_:range:)` inside `textView.textStorage?.beginEditing() / endEditing()` blocks

Start with two element types to prove the pattern end to end:

- **Headings:** walk `Heading` nodes; set font to `NSFont.systemFont(ofSize: sizeForLevel(level), weight: .bold)`
- **Bold (`Strong`):** walk `Strong` nodes; set font trait to `.bold` on the content range

Do NOT modify the text storage content — only attributes. The `**` delimiter characters stay in the buffer; their rendering is the Step 6 work.

### Step 6: Cursor-on-line reveal (the litmus)

**Files:** `LiveRenderTextView.swift`, `CursorLineTracker.swift`

This is the most important behavior in the spike. Implementation sketch:

1. Observe selection changes via `NSTextView` delegate method `textViewDidChangeSelection(_:)`
2. Compute the **logical line** containing the caret (use `NSString.lineRange(for:)` on the cursor position)
3. For the *previous* logical line (cached), re-apply the "collapsed" attributes — set delimiter ranges (`**`, `*`, `` ` ``) to `foregroundColor: .clear` **and** `NSAttributedString.Key(.init("NSHidden"))`-style hiding is tricky; simpler v1: use a very small font size (1pt) or `.ligature: 0` combined with `foregroundColor: NSColor.clear`. (**Record what actually worked in findings.**)
4. For the *current* logical line, apply the "revealed" attributes — restore the delimiter font/color so the `**` is visible
5. Implement the `**` → bold transform as a special case: the `Strong` AST node's content range gets `.bold`; the two delimiter sub-ranges get the visibility-toggling attributes

Expected behavior per the spec:
- Line `Plain **bold** plain` — bold rendered, `**` collapsed
- Move caret into the line — `**` delimiters appear in full size/color
- Move caret out — `**` delimiters collapse

**If the collapsed-attribute approach feels like a hack or fights TextKit 2:** stop and investigate the `NSTextLayoutManager`'s fragment rendering API. TextKit 2's `NSTextLayoutFragment` subclass can return custom `layoutFragmentFrame` that zero-widths specific ranges — more architecturally clean than attributes. Try attributes first (cheap); if you hit a wall, escalate to the layout-fragment approach and record the decision.

### Step 7: External-edit reflow

**Files:** `ExternalEditWatcher.swift`

Implement a class conforming to `NSFilePresenter`:

```swift
final class ExternalEditWatcher: NSObject, NSFilePresenter {
    var presentedItemURL: URL?
    var presentedItemOperationQueue: OperationQueue = .main
    var onChange: ((String) -> Void)?

    func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        if let newText = try? String(contentsOf: url, encoding: .utf8) {
            onChange?(newText)
        }
    }
}
```

Register with `NSFileCoordinator.addFilePresenter(_:)` when the file opens. On change, read new content and reconcile with the current buffer:
- If buffer has unsaved user edits (tracked via a `dirty` flag): show an alert offering to keep or replace — spike-level, not a proper three-way merge
- If buffer is clean: replace text, preserve caret position by character index on unchanged prefix

Deregister on window close or file change.

### Step 8: One XCUITest for the litmus

**Files:** `TextKit2LiveRenderSpikeUITests.swift` (new UI Testing target)

Add a **new UI Testing Bundle** to the project. Write one test:

```swift
final class CursorOnLineLitmusTests: XCTestCase {
    func testBoldDelimiterRevealsOnCursorEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uiTestMode", "--preloadSample", "sample-bold.md"]
        app.launch()

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5))

        // Preconditions: file contains "Plain **bold** plain"
        // Caret starts at end; bold delimiters should be collapsed.

        // Move caret into the line (simulate click mid-"bold")
        let rangeOfBold = textView.value as? String ?? ""
        XCTAssertTrue(rangeOfBold.contains("**bold**"))  // source text intact

        // Use XCUITest to move caret; check accessibility attributes
        textView.click()
        // Assertion sketch: we query the accessibility tree for attribute ranges
        // and verify that the `**` characters' AXFont or AXForegroundColor differs
        // when the caret is on vs off the line.
        // If AX doesn't expose per-range attributes cleanly — that's a finding.
    }
}
```

**If the test cannot be cleanly written, stop and record the finding in the transcript.** "XCUITest / the AX tree doesn't expose what we need to machine-verify attribute-level rendering" is a useful answer for later UI-test strategy.

---

## Testing

### Manual testing — the demo script

Run in order. After each step, write an observation line in the transcript (`transcript.md` in the spike directory), even if it's just "✓ as expected." Start the screen recording (Cmd+Shift+5 → record portion of screen) **before** Step A and stop after Step N.

**Sample files** — create these first at `spikes/d01_textkit2/samples/`:

- `sample-01-headings.md`:
  ```markdown
  # Top heading
  ## Second heading
  Plain paragraph.
  ### Third heading
  Another plain paragraph.
  ```
- `sample-02-inline.md`:
  ```markdown
  Plain **bold text** plain.
  Plain *italic text* plain.
  Plain `inline code` plain.
  A [link](https://example.com) to example.
  ```
- `sample-03-lists.md`:
  ```markdown
  - first
  - second
  - third

  1. alpha
  2. beta
  3. gamma
  ```
- `sample-04-code.md`:
  ```markdown
  Some prose.

  ```swift
  let x = 42
  print(x)
  ```

  More prose.
  ```
- `sample-05-large.md` — copy `docs/competitive-analysis.md` into this file (it's ~200 lines of real working markdown with tables, headings, links). Used for performance observation and subjective smoothness assessment.

**Demo steps:**

| # | Action | Expected observable |
|---|---|---|
| A | Launch the app | Empty window, title bar, no errors in Xcode console |
| B | Check console for `textLayoutManager != nil, layoutManager == nil` assertion | Both lines present; we're in the TextKit 2 code path |
| C | Open `sample-01-headings.md` | All three heading levels visible with visibly different font sizes and bold weight; plain paragraphs in regular weight |
| D | Move caret into "# Top heading" line | `#` character becomes visible (was collapsed); heading text unchanged |
| E | Move caret out to "Plain paragraph" line | `#` on the heading line collapses back out of view |
| F | Open `sample-02-inline.md` | `**`, `*`, `` ` `` delimiters collapsed; bold/italic/code rendering present |
| G | Click into `**bold text**` | `**` delimiters become visible on that line only |
| H | Type in a new sentence: press Return, then `Plain **new** plain` | As you type `**n`, the `**` is visible (caret is on line); after the second `**` completes, bold "new" is rendered with `**` still visible (caret on line) |
| I | Cmd+Z twice | Bold transform undoes coherently; no visual glitching; caret in reasonable place |
| J | Cmd+Shift+Z twice | Redo replays coherently |
| K | Open `sample-03-lists.md` | Bullet and numbered lists visible with indentation; list markers styled |
| L | Open `sample-04-code.md` | Fenced block rendered monospace with distinct background |
| M | Open `sample-05-large.md`; scroll through end to end with Page Down | Subjective — does it feel snappy? Any stutter? Record observation |
| N | With `sample-01-headings.md` open, in a terminal: `echo "" >> sample-01-headings.md; echo "# New heading from terminal" >> sample-01-headings.md` | Within ~1 second, the new heading appears in the editor; caret position preserved if editor buffer is clean |

### Performance measurement

After the demo script, one Instruments run with the **Time Profiler** template:

1. Open `sample-05-large.md` in the spike app
2. Open Xcode → Product → Profile (Cmd+I) with Time Profiler
3. Start recording
4. Move caret from top to line ~500 using the down-arrow key, one line at a time, steadily for ~5 seconds
5. Stop recording
6. In Instruments, filter on the selection-change handler frames; record median time per call

**Target:** median under 16ms per selection-change callback. If significantly higher, record the number and investigate attribute-batching strategies as a finding.

### Automated test

Run the one XCUITest from Step 8 via the Test navigator (Cmd+U after selecting the UI-test target). Record: pass, fail-but-meaningful, or couldn't-write-cleanly.

### Evidence capture

| Artifact | Path | How |
|---|---|---|
| Screen recording | `spikes/d01_textkit2/evidence/demo-recording.mov` | Cmd+Shift+5 → record portion → stop when demo ends |
| Demo transcript | `spikes/d01_textkit2/evidence/transcript.md` | Written by hand as the demo runs |
| Xcode console log | `spikes/d01_textkit2/evidence/console.log` | Copy from Xcode debug console at end of run |
| Instruments trace | `spikes/d01_textkit2/evidence/selection-perf.trace` | File → Save in Instruments |
| System info | `spikes/d01_textkit2/evidence/system.txt` | `sw_vers; xcodebuild -version; swift --version > system.txt` |
| Findings doc | `docs/current_work/stepwise_results/d01_textkit2_live_render_spike_COMPLETE.md` | Written after all of the above |

---

## Verification Checklist

- [ ] Xcode project builds clean, no warnings
- [ ] Startup assertion confirms TextKit 2 code path (`textLayoutManager != nil`, `layoutManager == nil`)
- [ ] All five sample files present and openable
- [ ] Demo script steps A–N executed with observations recorded in transcript
- [ ] Screen recording captured from start to end of demo
- [ ] Instruments trace captured; median selection-handler time recorded
- [ ] Single XCUITest runs (pass/fail/couldn't-write — all three are acceptable, just record which)
- [ ] System information captured
- [ ] Findings doc written with the explicit green/yellow/red recommendation and "what to do differently in D2" section
- [ ] All evidence files checked into the repo under `spikes/d01_textkit2/evidence/`
- [ ] `docs/stack-alternatives.md` Axis 2 updated with either a confirmation note (green/yellow) or a pivot change-entry (red)
- [ ] Spec Status transitions from **In Progress** → **Complete**

---

## Notes

- **Disposable code.** This project is a spike; it will not be shipped or reused as-is. Do not spend effort on architecture polish, test coverage, or comments beyond what's needed to run the demo. The value is in the findings doc, not in the code.
- **Time-box discipline.** The spec caps this at 5 working days. If at day 3 the cursor-on-line reveal is still not working and no path is visible, stop and record "5 days was not enough to validate with attributes alone; layout-fragment approach is the next thing to try" — that is itself a finding and a valid reason to produce a **yellow** recommendation rather than grind for a green one.
- **TextKit 2 API trap.** Setting `textView.usesAdaptiveColorMappingForDarkAppearance` or certain older APIs can silently flip you back to TextKit 1. Log both `textLayoutManager` and `layoutManager` on every significant initialization step as a safety net.
- **swift-markdown AST edge cases.** The library parses aggressively. Half-typed input like `**foo` (unclosed) may still produce a `Strong` node in some versions — verify empirically and record behavior in the findings. Our renderer should be tolerant of reparse volatility during typing.
- **Reference material.** Apple's WWDC 22 session "What's new in TextKit and text-related features" is the canonical primer. Sample code from Apple is thin; Swift OSS editors on TextKit 2 are rare (Zed uses its own renderer; most others are still on TextKit 1 or WKWebView). Expect to be pioneering.
- **Findings doc outline** — start here when writing `d01_textkit2_live_render_spike_COMPLETE.md`:
  1. TL;DR (one paragraph, plus green/yellow/red)
  2. Demo results per step A–N (pass / fail / surprise)
  3. APIs that worked — list with docs links
  4. APIs that were traps — list with what went wrong
  5. Performance observation with Instruments number
  6. Cursor-on-line reveal — approach that worked; approach that didn't
  7. External-edit reflow — how clean was the experience
  8. XCUITest outcome — passed / failed / unwriteable, and what that tells us
  9. Recommendation with reasoning
  10. What to do differently in D2
