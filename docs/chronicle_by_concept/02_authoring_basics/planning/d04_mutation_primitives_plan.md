# D4: Mutation Primitives + Keyboard Bindings — Implementation Instructions

**Spec:** `d04_mutation_primitives_spec.md`
**Created:** 2026-04-22

---

## Overview

Add the full set of markdown formatting mutations (bold, italic, inline code, link, heading 0–6, bullet list, numbered list) triggered by Word/Docs-familiar keyboard shortcuts. Uniform toggle semantics. Code-block safety via attribute probe. One undo step per command. No visible UI chrome changes in D4.

Promotes `Sources/Keyboard/` from D2 stub to real module; adds `Sources/Mutations/` from scratch.

---

## Prerequisites

- [ ] D2 Complete; built .app launches and renders cleanly
- [ ] `xcodegen` + Xcode 16.2 still available (D1 prerequisites)
- [ ] `DEVELOPER_DIR` sourced in pane 2
- [ ] Spec Open Questions answered or recommendations accepted (see §Notes below)

---

## Implementation Steps

### Step 1 — MutationPrimitive protocol + shared types

**File:** `Sources/Mutations/MutationPrimitive.swift`

```swift
import Foundation
import Markdown

protocol MutationPrimitive {
    static var identifier: String { get }
    static func apply(to input: MutationInput) -> MutationOutput?
}

struct MutationInput {
    let source: String
    let selection: NSRange
    let document: Document
    let nsSource: NSString   // precomputed for offset math
    let converter: SourceLocationConverter
}

struct MutationOutput {
    let newSource: String
    let newSelection: NSRange
}
```

Include small utility helpers here or in a sibling file (e.g., `MutationHelpers.swift`): line-range expansion, trim-trailing-newline for selection normalization, AST walk for a matching node type.

### Step 2 — Code-block safety probe

**File:** `Sources/Mutations/CodeBlockSafety.swift`

```swift
import AppKit
import Foundation

enum CodeBlockSafety {
    /// Returns true if the selection starts inside (or at a character
    /// tagged as) a code-block-styled range in the text storage.
    /// Per spec Open Question 5, we probe start-of-selection only; this
    /// is fast and covers the common case (user puts caret in a code
    /// block and presses Cmd+B).
    static func isInsideCodeBlock(selectionStart: Int, in storage: NSTextStorage) -> Bool {
        guard storage.length > 0 else { return false }
        let probe = min(max(0, selectionStart), storage.length - 1)
        let bg = storage.attribute(.backgroundColor, at: probe, effectiveRange: nil) as? NSColor
        return bg == Typography.codeBackground
    }
}
```

### Step 3 — Bold mutation (the template for all selection-based)

**File:** `Sources/Mutations/BoldMutation.swift`

```swift
import Foundation
import Markdown

enum BoldMutation: MutationPrimitive {
    static let identifier = "mutation.bold"
    static let marker = "**"

    static func apply(to input: MutationInput) -> MutationOutput? {
        // Normalize: trim trailing newline from selection (spec OQ #4)
        let sel = MutationHelpers.trimTrailingNewline(input.selection, in: input.nsSource)

        if let strongRange = MutationHelpers.enclosingNodeRange(of: Strong.self, containing: sel, in: input.document, using: input.converter) {
            // Unwrap: remove the two leading and two trailing `**`.
            return MutationHelpers.unwrap(sel: sel, wrappedRange: strongRange, markerLength: marker.count, in: input.source)
        }

        // Wrap
        return MutationHelpers.wrap(sel: sel, with: marker, in: input.source)
    }
}
```

Italic, InlineCode, Link follow the same pattern with different marker + different enclosing node types.

### Step 4 — Italic, InlineCode, Link (selection-based toggles)

**Files:** `Sources/Mutations/{ItalicMutation, InlineCodeMutation, LinkMutation}.swift`

- **Italic (Cmd+I):** `*` marker, enclosing node `Emphasis`.
- **Inline code (Cmd+E):** `` ` `` marker, enclosing node `InlineCode`. NOTE: InlineCode has no children in swift-markdown; enclosing-range detection uses the node's source range.
- **Link (Cmd+K):** special — unwrap removes surrounding `[sel](url)`; wrap inserts `[sel](|)` with caret inside parens. When no selection, insert `[](|)` with caret inside `[]` (spec OQ #2 recommendation).

Link's `apply` is the most involved. Sketch:

```swift
static func apply(to input: MutationInput) -> MutationOutput? {
    let sel = input.selection
    if let linkRange = MutationHelpers.enclosingNodeRange(of: Link.self, containing: sel, ...) {
        // Unwrap: replace [text](url) with just text, caret preserved
        ...
    }
    if sel.length == 0 {
        // Insert [](|) at caret; place caret inside []
        return MutationHelpers.insert(at: sel.location, text: "[]()", newCaretOffset: 1)
    }
    // Wrap: extract selected text, produce [selected](), caret inside ()
    return MutationHelpers.wrapAsLink(sel: sel, in: input.source)
}
```

### Step 5 — HeadingMutation (level 0–6, line-based)

**File:** `Sources/Mutations/HeadingMutation.swift`

```swift
enum HeadingMutation {
    /// Level 0 = body (remove heading). Levels 1–6 = H1–H6.
    static func make(level: Int) -> MutationPrimitive.Type {
        return Level(rawValue: level)?.primitive ?? Level.one.primitive
    }
}

// Each level is its own primitive type (Heading1, Heading2, ..., Body0)
// so they each have a static identifier matching the keyboard binding.
```

Implementation per level:

```swift
enum Heading1Mutation: MutationPrimitive {
    static let identifier = "mutation.heading1"
    static func apply(to input: MutationInput) -> MutationOutput? {
        applyHeading(level: 1, to: input)
    }
}
// Similar for 2..6 and 0 (body)

// Shared impl:
private func applyHeading(level: Int, to input: MutationInput) -> MutationOutput? {
    let lines = MutationHelpers.linesCovering(input.selection, in: input.nsSource)
    let states = lines.map { MutationHelpers.headingLevel(of: $0, in: input.document, using: input.converter) }
    let uniform = states.allSatisfy { $0 == level }
    let target = uniform ? 0 : level
    return MutationHelpers.rewriteLines(lines, in: input.source, transform: { line in
        MutationHelpers.setHeadingLevel(line: line, toLevel: target)
    })
}
```

`setHeadingLevel(line:toLevel:)` strips any existing `#`-prefix + one trailing space, then prepends the new prefix (if target > 0).

### Step 6 — BulletListMutation and NumberedListMutation

**Files:** `Sources/Mutations/{BulletListMutation, NumberedListMutation}.swift`

Same line-based uniform-toggle shape as headings. For bullet: prefix `- `. For numbered: per-line `1. `, `2. `, `3. `. Removal strips the prefix.

### Step 7 — MutationResolver

**File:** `Sources/Mutations/MutationResolver.swift`

```swift
enum MutationResolver {
    private static let registry: [String: MutationPrimitive.Type] = [
        BoldMutation.identifier: BoldMutation.self,
        ItalicMutation.identifier: ItalicMutation.self,
        InlineCodeMutation.identifier: InlineCodeMutation.self,
        LinkMutation.identifier: LinkMutation.self,
        Heading1Mutation.identifier: Heading1Mutation.self,
        Heading2Mutation.identifier: Heading2Mutation.self,
        Heading3Mutation.identifier: Heading3Mutation.self,
        Heading4Mutation.identifier: Heading4Mutation.self,
        Heading5Mutation.identifier: Heading5Mutation.self,
        Heading6Mutation.identifier: Heading6Mutation.self,
        BodyMutation.identifier: BodyMutation.self,
        BulletListMutation.identifier: BulletListMutation.self,
        NumberedListMutation.identifier: NumberedListMutation.self,
    ]

    static func primitive(for identifier: String) -> MutationPrimitive.Type? {
        registry[identifier]
    }
}
```

### Step 8 — KeyboardBindings table

**File:** `Sources/Keyboard/KeyboardBindings.swift`

```swift
import AppKit

enum KeyboardBindings {
    struct Chord {
        let modifiers: NSEvent.ModifierFlags
        let key: String   // characters-ignoring-modifiers, lowercased
    }
    struct Binding {
        let chord: Chord
        let commandIdentifier: String
    }

    static let all: [Binding] = [
        Binding(chord: Chord(modifiers: [.command], key: "b"),
                commandIdentifier: "mutation.bold"),
        Binding(chord: Chord(modifiers: [.command], key: "i"),
                commandIdentifier: "mutation.italic"),
        Binding(chord: Chord(modifiers: [.command], key: "e"),
                commandIdentifier: "mutation.inlineCode"),
        Binding(chord: Chord(modifiers: [.command], key: "k"),
                commandIdentifier: "mutation.link"),
        Binding(chord: Chord(modifiers: [.command, .shift], key: "7"),
                commandIdentifier: "mutation.numberedList"),
        Binding(chord: Chord(modifiers: [.command, .shift], key: "8"),
                commandIdentifier: "mutation.bulletList"),
        Binding(chord: Chord(modifiers: [.command, .option], key: "0"),
                commandIdentifier: "mutation.body"),
        Binding(chord: Chord(modifiers: [.command, .option], key: "1"),
                commandIdentifier: "mutation.heading1"),
        Binding(chord: Chord(modifiers: [.command, .option], key: "2"),
                commandIdentifier: "mutation.heading2"),
        Binding(chord: Chord(modifiers: [.command, .option], key: "3"),
                commandIdentifier: "mutation.heading3"),
        Binding(chord: Chord(modifiers: [.command, .option], key: "4"),
                commandIdentifier: "mutation.heading4"),
        Binding(chord: Chord(modifiers: [.command, .option], key: "5"),
                commandIdentifier: "mutation.heading5"),
        Binding(chord: Chord(modifiers: [.command, .option], key: "6"),
                commandIdentifier: "mutation.heading6"),
    ]

    static func match(event: NSEvent) -> Binding? {
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let eventKey = (event.charactersIgnoringModifiers ?? "").lowercased()
        return all.first { $0.chord.modifiers == eventMods && $0.chord.key == eventKey }
    }
}
```

### Step 9 — CommandDispatcher

**File:** `Sources/Keyboard/CommandDispatcher.swift`

```swift
import AppKit
import Markdown

final class CommandDispatcher {
    static let shared = CommandDispatcher()
    private init() {}

    /// Dispatches a command. Returns true if the command was handled
    /// (mutation applied or safely no-op'd); false if not recognized.
    @discardableResult
    func dispatch(identifier: String, in textView: NSTextView) -> Bool {
        guard let primitive = MutationResolver.primitive(for: identifier) else { return false }
        guard let storage = textView.textStorage else { return false }

        let selection = textView.selectedRange()

        // Code-block safety (spec §3)
        if CodeBlockSafety.isInsideCodeBlock(selectionStart: selection.location, in: storage) {
            return true  // handled = no-op
        }

        let source = storage.string
        let nsSource = source as NSString
        let converter = SourceLocationConverter(source: source)
        let document = Document(parsing: source)

        let input = MutationInput(
            source: source,
            selection: selection,
            document: document,
            nsSource: nsSource,
            converter: converter
        )

        guard let output = primitive.apply(to: input) else { return true }

        // Apply as a single undo group.
        textView.undoManager?.beginUndoGrouping()
        defer { textView.undoManager?.endUndoGrouping() }

        // Replace full text via NSTextView (which integrates with undo
        // properly on TextKit 2 — the shouldChangeText / didChangeText
        // lifecycle handles registration).
        let fullRange = NSRange(location: 0, length: storage.length)
        if textView.shouldChangeText(in: fullRange, replacementString: output.newSource) {
            storage.replaceCharacters(in: fullRange, with: output.newSource)
            textView.didChangeText()
        }
        textView.setSelectedRange(output.newSelection)
        return true
    }
}
```

### Step 10 — Hook into LiveRenderTextView

**File:** `Sources/Editor/LiveRenderTextView.swift` (modify)

```swift
override func keyDown(with event: NSEvent) {
    if let binding = KeyboardBindings.match(event: event),
       CommandDispatcher.shared.dispatch(identifier: binding.commandIdentifier, in: self) {
        return
    }
    super.keyDown(with: event)
}
```

That's the only editor change needed. Dispatcher calls trigger `didChangeText`, which triggers our existing `textDidChange` path in `EditorContainer.Coordinator`, which runs the renderer and cursor tracker — same code path as typing.

### Step 11 — Retire Sources/Keyboard/README.md

Delete the stub README (we now have real Swift files in `Keyboard/`). The module is live.

### Step 12 — UITest extension

**File:** `UITests/MutationKeyboardTests.swift` (new)

```swift
import XCTest

final class MutationKeyboardTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBoldMutationWrapsSelection() throws {
        let app = XCUIApplication()
        app.launch()

        let editor = app.descendants(matching: .any)["md-editor.main-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))

        // Type a word, select it, Cmd+B, read back the value.
        editor.click()
        editor.typeText("hello")
        editor.typeKey("a", modifierFlags: .command)  // select all
        editor.typeKey("b", modifierFlags: .command)  // bold

        // Read the editor value via AX. With source intact, the raw
        // source should contain "**hello**" (or similar).
        let text = (editor.value as? String) ?? ""
        XCTAssertTrue(text.contains("**hello**"),
                      "expected **hello** in source; got: \(text)")
    }
}
```

Note: on a freshly-launched app with no file open, typing goes into an empty buffer. This test works against the empty-buffer state; if we discover that the app requires a file to be open before typing, we adjust (pre-seed via a URL arg or similar).

### Step 13 — Regenerate, build, test

```bash
source scripts/env.sh
xcodegen generate
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
  -configuration Debug -derivedDataPath ./.build-xcode build
xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
  -destination 'platform=macOS' -derivedDataPath ./.build-xcode test
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

---

## Testing

### Manual exploratory (per spec §4.5)

Demo script in `apps/md-editor-mac/evidence/d04/transcript.md`, screen-recorded. 11 steps, all keyboard-only. Expected observables per spec. Report per-step pass/fail.

### Automated

- `xcodebuild test` runs both `LaunchSmokeTests` (from D2) and the new `MutationKeyboardTests`. All must pass.

### Verification Checklist

- [ ] Sources/Mutations/ contains 10 mutation files + helpers + safety + resolver + protocol = ~14 .swift files
- [ ] Sources/Keyboard/README.md removed; KeyboardBindings.swift and CommandDispatcher.swift present
- [ ] LiveRenderTextView.swift has a keyDown override
- [ ] `rg --type swift 'layoutManager\b' Sources/` → zero non-comment hits (§2.2)
- [ ] `rg --type swift 'accessibilityIdentifier' Sources/` → same set as D2 (no new interactive views in D4)
- [ ] Demo script complete with evidence files
- [ ] UITest green
- [ ] Completion doc at `docs/current_work/stepwise_results/d04_mutation_primitives_COMPLETE.md`
- [ ] roadmap_ref.md updated to mark D4 complete

---

## Notes

- **Open Questions from the spec:** the spec lists 5 with recommendations. Before starting Step 1, confirm Rick's decisions (defaults: Cmd+E for inline code; link-with-no-selection produces `[](|)`; heading replaces list prefix; trim trailing newline; start-of-selection code-block probe). Document any deviations in the COMPLETE doc.
- **`applyHeading` implementation is the most finicky** — heading regex on a line ("^#{1,6} " → strip, optionally re-prepend). Write unit tests first for this helper: given a line, given a target level, expected output. 8-10 test cases catch most edge cases.
- **Undo integration via `shouldChangeText`/`didChangeText` is load-bearing** — do not replace storage directly via `storage.replaceCharacters` without the shouldChange/didChange sandwich, or undo won't register. This is a subtle AppKit requirement.
- **The swift-markdown AST is re-parsed per mutation.** Given our ~300-line test corpus, this is fast (<5ms typical). Don't preemptively optimize; if we see lag in the demo, use a cached-AST approach. Note in COMPLETE if observed.
- **Commit cadence:** one commit after Step 2 (protocols + safety compile), one after Step 7 (all mutations compile), one after Step 11 (dispatcher wired), one after Step 13 (build + test green). Four commits total for D4.
- **Spike-quality edge cases are acceptable.** For D4, if a specific selection corner (e.g., selection ending at EOF with no trailing newline) produces an odd result, note it in COMPLETE as a D5+ polish item rather than blocking D4.
