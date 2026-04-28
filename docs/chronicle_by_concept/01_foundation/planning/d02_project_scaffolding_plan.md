# D2: Project Scaffolding — Implementation Instructions

**Spec:** `d02_project_scaffolding_spec.md`
**Created:** 2026-04-22

---

## Overview

Promote the D1 TextKit 2 spike into a real Xcode project at `apps/md-editor-mac/` with an intentional module structure that reflects the nine cross-OS abstractions from `docs/stack-alternatives.md`. Fix the five D1 findings during the lift. Honor every standard in `docs/engineering-standards_ref.md` from the first commit.

No new features; same behavior as the spike.

---

## Prerequisites

- [ ] D1 Complete — findings doc at `docs/current_work/stepwise_results/d01_textkit2_live_render_spike_COMPLETE.md`
- [ ] Xcode 16.2 or later available (verified in D1)
- [ ] xcodegen available (installed in D1: `brew install xcodegen`)
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` sourced into pane 2 (same approach D1 used)
- [ ] Spike source files at `spikes/d01_textkit2/Sources/TextKit2LiveRenderSpike/` intact and readable for reference during the lift

---

## Implementation Steps

### Step 1 — Create the project directory and xcodegen spec

**Files:** `apps/md-editor-mac/project.yml`, `apps/md-editor-mac/Info.plist`

Create `apps/md-editor-mac/` alongside the existing `docs/` and `spikes/`. Write a `project.yml` that:
- Names the product **MdEditor** (scheme, target, product name all `MdEditor`)
- Bundle identifier **`ai.portablemind.md-editor`** (engineering-standards §1.2)
- Deployment target **macOS 14.0** (Open Question 1 recommendation)
- Single executable target + single UI Testing bundle target
- Adds the `swift-markdown` package dependency (same URL and version pin as D1)
- Points `info.path: Info.plist` at a hand-maintained Info.plist; `GENERATE_INFOPLIST_FILE: NO`
- Settings: `SWIFT_VERSION: 5.10`, `ENABLE_HARDENED_RUNTIME: NO` (D3 flips this to YES), `CODE_SIGN_STYLE: Automatic`, `CODE_SIGN_IDENTITY: -` (ad-hoc for dev; D3 changes to Developer ID)

Write the Info.plist with the full production key-set per engineering-standards §1.3. Include `SUFeedURL` and `SUPublicEDKey` as empty strings with a `<!-- TODO(D3): populate when Sparkle lands -->` comment.

### Step 2 — Create the module directory skeleton

**Files:** `apps/md-editor-mac/Sources/{App,DocumentTypes,Editor,Editor/Renderer,Files,Accessibility,Support,Handoff,Toolbar,Keyboard,Settings,Localization}/`

For the "stub-only" modules (Handoff, Toolbar, Keyboard, Settings), create the directory and a `README.md` stating the abstraction's purpose and the deliverable expected to implement it. No `.swift` source files yet unless the stub requires a protocol declaration for future code to reference.

For the "real code at D2" modules (App, DocumentTypes, Editor, Editor/Renderer, Files, Accessibility, Support, Localization), the directory will be filled in the subsequent steps.

### Step 3 — Support module: Typography + render types

**Files:** `Sources/Support/Typography.swift`, `Sources/Support/RenderTypes.swift`

Lift the typography struct from `SpikeTypes.swift`. Rename:
- `SpikeTypography` → `Typography`
- Keep `baseFontSize`, `baseFont` (unchanged per spec Open Question 5 — typography switch deferred)
- The syntax-role attribute-key constant moves here under `Typography.syntaxRoleKey`

In `RenderTypes.swift`, lift `AttributeAssignment`, `SyntaxRole`, `SyntaxSpan` as shared types, and **introduce `RenderResult`**:

```swift
struct RenderResult {
    let assignments: [AttributeAssignment]
    let spans: [SyntaxSpan]
}
```

(Spike had this as `MarkdownRenderResult` inside the renderer. Promoting to a shared type satisfies the DocumentType abstraction in Step 5.)

### Step 4 — Accessibility module: identifiers constants

**Files:** `Sources/Accessibility/AccessibilityIdentifiers.swift`

```swift
enum AccessibilityIdentifiers {
    static let mainEditor = "md-editor.main-editor"
    static let openFileButton = "md-editor.open-file-button"
    static let mainWindow = "md-editor.main-window"
    // Add one constant per interactive NSView created in the app.
}
```

Every later step that creates an interactive NSView sets its `accessibilityIdentifier` from this enum. Never hardcode strings at the usage site.

### Step 5 — DocumentTypes module: registry + MarkdownDocumentType

**Files:** `Sources/DocumentTypes/DocumentType.swift`, `Sources/DocumentTypes/DocumentTypeRegistry.swift`, `Sources/DocumentTypes/MarkdownDocumentType.swift`

`DocumentType.swift`:
```swift
protocol DocumentType {
    static var fileExtensions: [String] { get }
    func render(_ source: String) -> RenderResult
}
```

`DocumentTypeRegistry.swift`:
```swift
final class DocumentTypeRegistry {
    static let shared = DocumentTypeRegistry()
    private var registered: [(extensions: [String], make: () -> any DocumentType)] = []

    private init() {
        register(MarkdownDocumentType.self)
    }

    func register<T: DocumentType>(_ type: T.Type) {
        registered.append((extensions: T.fileExtensions, make: { T() }))
    }

    func type(for url: URL) -> (any DocumentType)? {
        let ext = url.pathExtension.lowercased()
        return registered.first(where: { $0.extensions.contains(ext) })?.make()
    }
}
```

`MarkdownDocumentType.swift`:
```swift
struct MarkdownDocumentType: DocumentType {
    static let fileExtensions = ["md", "markdown"]
    private let renderer = MarkdownRenderer()
    func render(_ source: String) -> RenderResult { renderer.render(source) }
}
```

### Step 6 — Editor/Renderer: lift with finding #3 and #4 fixes

**Files:** `Sources/Editor/Renderer/MarkdownRenderer.swift`, `Sources/Editor/Renderer/SourceLocationConverter.swift`

Lift the hand-rolled walker pattern from the spike. Change:
1. Extract the UTF-8 line/column → UTF-16 offset logic into a new `SourceLocationConverter` class that is initialized with the source string and caches line-start offsets. This is the fix for findings #3 and #4.
2. `RenderVisitor` instantiates and uses `SourceLocationConverter` rather than walking the string for every node.
3. `visitCodeBlock` now tags the opening and closing `` ``` `` fence markers as delimiters. Detect the fence character run at the start of the block's range (opening) and at the line preceding the block's trailing boundary (closing).
4. Return `RenderResult` (the shared type) instead of the spike's local `MarkdownRenderResult`.

```swift
final class SourceLocationConverter {
    private let source: NSString
    private let lineStarts: [Int]  // UTF-16 offset of the start of each 1-based line

    init(source: String) {
        self.source = source as NSString
        var starts = [0]
        let length = self.source.length
        var i = 0
        while i < length {
            let ch = self.source.character(at: i)
            i += 1
            if ch == unichar(UnicodeScalar("\n").value) {
                starts.append(i)
            }
        }
        self.lineStarts = starts
    }

    func nsOffset(line: Int, column: Int) -> Int {
        guard line >= 1, line <= lineStarts.count else { return NSNotFound }
        let base = lineStarts[line - 1]
        return min(base + (column - 1), source.length)
    }
}
```

Unit tests for `SourceLocationConverter` and for the inline-code and code-block range computation (findings #3 and #4) should be added in the same step — see Testing.

### Step 7 — Editor/Renderer: cursor tracker with finding #2 fix

**Files:** `Sources/Editor/Renderer/CursorLineTracker.swift`

Lift from the spike. Add `collapseAllDelimiters(in: NSTextView)`:
```swift
func collapseAllDelimiters(in textView: NSTextView) {
    guard let storage = textView.textStorage else { return }
    let fullRange = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.enumerateAttribute(Typography.syntaxRoleKey, in: fullRange, options: []) { value, range, _ in
        if (value as? String) == "delimiter" {
            applyCollapsed(to: storage, in: range)
        }
    }
    storage.endEditing()
    revealedLineRange = nil
}
```

(Where `applyCollapsed` is extracted from the existing per-line private method so it takes an arbitrary range rather than a line range.)

### Step 8 — Editor: container + live-render text view

**Files:** `Sources/Editor/EditorContainer.swift`, `Sources/Editor/LiveRenderTextView.swift`

Lift `EditorContainer` with these changes:
- Never references `NSTextView.layoutManager` — the startup diagnostic only checks `textLayoutManager` (engineering-standards §2.2).
- Uses `DocumentTypeRegistry.shared.type(for: fileURL)` rather than hardcoding the markdown renderer. The type's `render(_:)` returns `RenderResult`; the container applies assignments the same way as the spike.
- After the initial render in `replaceAndRender`, calls `cursorTracker.collapseAllDelimiters(in: textView)` before the first `updateVisibility`. (Finding #2 fix.)
- Sets `textView.setAccessibilityIdentifier(AccessibilityIdentifiers.mainEditor)` at construction. (Finding #5.)

`LiveRenderTextView.swift` can be a lightweight `NSTextView` subclass if we need per-view customization; for D2 v1 a typealias or direct `NSTextView` instance is fine, but file must exist as a home for future customization.

### Step 9 — Files module: external-edit watcher

**Files:** `Sources/Files/ExternalEditWatcher.swift`

Lift verbatim from the spike, modulo any namespace renames. No behavioral changes; it's already clean.

### Step 10 — App module: entry + window + file picker

**Files:** `Sources/App/MdEditorApp.swift`

Lift `SpikeApp` → `MdEditorApp`. Additions:
- Accessibility identifier on the Open… button: `AccessibilityIdentifiers.openFileButton`.
- Accessibility identifier on the window (via scene or directly on the NSWindow when it first becomes key — via a `.onAppear` hook into the NSWindow).
- Use `DocumentTypeRegistry.shared.type(for: url)` to validate the picked file has a registered type; if not, silently skip (v1; explicit UX when we add document-type selection).

### Step 11 — Localization module

**Files:** `Sources/Localization/Localizable.xcstrings`

Create the new-style `.xcstrings` catalog with an English-only table. Add strings we use in UI (`"Open…"`, `"Untitled"` — the two visible in the spike). Wire `Localizable` lookups in `MdEditorApp` so strings aren't hardcoded. Even with one language, setting this up now costs nothing and avoids a retrofit later.

### Step 12 — Stub modules: Handoff / Toolbar / Keyboard / Settings

Each gets a `README.md` of the form:
```markdown
# {Module} (stub — D2)

Purpose: {one sentence naming the abstraction from stack-alternatives.md §"Architecture lessons to capture for Windows and Linux"}.
Status: Stub only. Implementation arrives with its feature deliverable (TBD).
D2 commitment: the module directory exists so future deliverables plug in at a stable boundary.
```

No Swift source. No protocols declared yet (add them at the point of use — avoids dead abstractions).

### Step 13 — UITests: launch + identifier-based query

**Files:** `UITests/LaunchSmokeTests.swift`

```swift
final class LaunchSmokeTests: XCTestCase {
    func testAppLaunchesAndMainEditorIsAccessible() throws {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        // Query by identifier (standard §2.1) — NOT by element type.
        let editor = app.descendants(matching: .any)[AccessibilityIdentifiers.mainEditor]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }
}
```

### Step 14 — Freeze or remove the spike

**Files:** `spikes/d01_textkit2/README.md` (modify)

Per spec Open Question 4 recommendation, retain `spikes/d01_textkit2/` with a prominent banner:

```markdown
# [FROZEN] D1 TextKit 2 Spike — Do Not Modify

This spike was promoted to `apps/md-editor-mac/` in D2. It is retained here as a minimal known-good reference and MUST NOT BE MODIFIED. If you find a discrepancy between this and the real app, update the real app; the spike stays frozen.

See `docs/current_work/stepwise_results/d01_textkit2_live_render_spike_COMPLETE.md` for context.
```

Delete the spike's `.build-xcode/` directory (gitignored anyway, but cleanup).

### Step 15 — Update CLAUDE.md

**Files:** `CLAUDE.md` (project root)

Update:
- Running the project section — with the real `xcodebuild` command and `open` path.
- Project structure section — add `apps/md-editor-mac/` layout.
- Note the spike is frozen.

### Step 16 — Generate, build, launch

From pane 2:
```bash
source apps/md-editor-mac/scripts/env.sh  # or export DEVELOPER_DIR inline
cd apps/md-editor-mac
xcodegen generate
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
  -configuration Debug -derivedDataPath ./.build-xcode build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

The app should open, look like the spike did at the end of D1, but with findings #2, #3, #4 visibly fixed.

---

## Testing

### Manual exploratory (Native Phase 1, abbreviated demo)

Run in order; record observations in `apps/md-editor-mac/evidence/d02/transcript.md`. Start screen recording before step A; stop after step E.

| # | Action | Expected observable |
|---|---|---|
| A | Launch app | Window appears, in Dock, in alt-tab |
| B | `Cmd+O` → pick `docs/CLAUDE.md` | Document opens; **all delimiters collapsed** on initial render (finding #2 fix — verify `##` gone on headings, `**…**` gone around bold, `` ` `` gone around inline code) |
| C | Click into the first heading line | `#` characters on that line become visible |
| D | Click into the line containing `` `.md`-files-on-disk `` | **Inline-code region is exactly `.md`** with no character drops; backticks become visible on caret-in (finding #3 fix) |
| E | Open a file with a fenced code block (create `samples/code.md` if needed) | **Content lines inside the fence have monospace background**; `` ``` `` fences collapse on caret-leave (finding #4 fix) |

### Automated tests

- **Unit tests (first real test suite):** `SourceLocationConverterTests` — a small set of known-source, known-range assertions covering Heading, Strong, Emphasis, InlineCode, CodeBlock nodes. At minimum 5 tests. Add `Tests/` target or inline as `SourcesTests/`.
- **UI smoke test:** `UITests/LaunchSmokeTests.swift` from Step 13. Must pass via `xcodebuild test -scheme MdEditor -destination 'platform=macOS'`.

### Verification Checklist

- [ ] `xcodebuild build` clean — no warnings introduced by D2
- [ ] `xcodebuild test` passes
- [ ] Demo steps A–E produce expected observables
- [ ] `rg --type swift 'layoutManager\\b' apps/md-editor-mac/Sources/` → no matches
- [ ] `rg --type swift 'accessibilityIdentifier' apps/md-editor-mac/Sources/` → at least 3 matches (main editor, open button, main window)
- [ ] `rg --type swift 'Spike' apps/md-editor-mac/Sources/` → no matches (all spike-namespaced types renamed)
- [ ] Bundle identifier in Info.plist = `ai.portablemind.md-editor` (standard §1.2)
- [ ] Full Info.plist key-set present (standard §1.3) — verify with `/usr/libexec/PlistBuddy -c "Print" Info.plist`
- [ ] Spike directory frozen with `README.md` banner (Step 14)
- [ ] CLAUDE.md updated (Step 15)
- [ ] Evidence files checked in: `evidence/d02/transcript.md`, `evidence/d02/demo-recording.mov`, `evidence/d02/xcodebuild-build.log`, `evidence/d02/xcodebuild-test.log`

---

## Notes

- **Sequencing:** Steps 1–4 set up the skeleton; 5–7 lift the renderer with fixes; 8–11 lift the app shell; 12 adds stubs; 13 adds the UI test; 14–15 are cleanup; 16 is verify. Any step that fails to build should be fixed before proceeding.
- **Commit cadence:** I'll commit after Step 4 (skeleton builds empty), after Step 11 (app runs end-to-end), after Step 13 (test passes), and after Step 16 (final). Four commits for D2 feels right given the scope.
- **If `xcodegen` wants different flags for a multi-target project:** may need a second `scheme` entry for tests and possibly a `testTargets` array. Consult xcodegen docs at that step; not pre-specifying here.
- **The typography trap:** D2 keeps the body monospace per spec Out-of-Scope. Resist the temptation to "just quickly switch to proportional" during the lift; that's a separate, intentional deliverable because it changes the product's feel and we want to observe that change cleanly.
- **The `.layoutManager` grep is not just a one-time check:** per engineering-standards §2.2, this should eventually be a pre-commit hook. Leave a TODO in `CLAUDE.md` to set one up during D3 or earlier.
