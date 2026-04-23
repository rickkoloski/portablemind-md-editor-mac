# md-editor-mac — Stack Alternatives & Recommendation

**Companion to:** `vision.md`, `competitive-analysis.md`, `portablemind-positioning.md`
**Scope:** The macOS-specific implementation stack for md-editor v1.
**Note on Principle 2:** This doc *is* a per-OS artifact, not a shared one. The parallel docs for Windows and Linux come later, informed by the architecture lessons captured here (final section).
**Date:** 2026-04-22

---

## Purpose

Pick the stack for md-editor-mac. The vision already narrows the space significantly (native per-OS, not Electron; Word/Docs-familiar authoring; Level 1 and Level 2 agent-aware). This doc enumerates the remaining real alternatives, weighs them, and commits to a specific stack — while preserving the architectural discipline that lets Windows and Linux versions be genuinely native rather than ports of the mac code.

## Decision axes

Five choices, not one. Treating them as independent axes keeps the tradeoffs legible:

1. **Language & UI framework** — what we write the app in.
2. **Text-editing engine** — what renders and handles the content area. This is the largest single decision in the app.
3. **Markdown parsing library** — how we turn text into a tree we can render and manipulate.
4. **File-system access and watching** — how we open folders and detect external edits.
5. **Packaging, signing, and updates** — how the app gets onto a user's machine and stays current.

Each section below lists the alternatives considered, the tradeoffs, and the recommendation.

---

## Axis 1 — Language & UI framework

### Alternatives considered

| Option | Native feel | Cross-platform portability of code | Ramp cost | Viability for us |
|---|---|---|---|---|
| **Swift + SwiftUI (with AppKit where needed)** | Highest | None (Apple-only) — by design | Medium (new language) | Recommended |
| Swift + AppKit only | Highest | None | Medium-high (older patterns, more boilerplate) | Viable but redundant |
| Objective-C + AppKit | High | None | Medium | No reason to pick today |
| Rust + native bindings (cacao, winit, etc.) | Medium | High (same language on other OSes) | Very high (immature mac bindings) | Rejected |
| React Native for macOS | Low-medium | Medium (RN Windows exists, Linux doesn't) | Low for us (TS/React fluent) | Rejected — contradicts Principle 2 |
| Flutter desktop | Low (non-native look) | High | Medium | Rejected — contradicts Principle 2 |
| Tauri 2 (native webview + Rust backend) | Medium (web UI in native shell) | High | Medium | Rejected — also a hybrid we said we'd avoid |
| Electron | Lowest | Highest | Lowest | Rejected by vision |

### Recommendation: Swift + SwiftUI as primary, AppKit where SwiftUI falls short

**Why.** SwiftUI is now mature enough (as of macOS 14/15) for the chrome, menus, navigation, settings, and most views of a markdown editor. It's declarative, composable, and keeps the mac code concise. Where SwiftUI still has gaps — custom text services, printing, certain context-menu behaviors, some accessibility affordances — we drop into AppKit via `NSViewRepresentable`. This is the pattern Apple's own apps and every serious native mac app (Ivory, Ice Cubes, NetNewsWire) follow.

**Why not Rust + bindings.** Attractive in principle because the language transfers across mac/win/linux. In practice the Rust mac bindings (cacao, objc2) are still rough; we'd be fighting the bindings instead of the product. Zed's approach (custom Rust + GPUI) works for them because they shipped a general-purpose editor and could afford that investment. We can't.

**Why not a cross-platform framework.** React Native for macOS, Flutter desktop, and Tauri are all different flavors of the same compromise: they save on line-count at the cost of native feel. Vision Principle 2 rules that out explicitly. Writing three native apps is deliberate cost we're paying to earn the positioning.

**Ramp note.** You (Rick) haven't written Swift before, but you've landed in new languages plenty of times and you'll be working with Claude Code assistance on syntax and idiom. SwiftUI's declarative shape will feel familiar after React. The biggest adjustment will be value vs. reference semantics and Swift's type-system strictness; we'll flag patterns as they come up.

---

## Axis 2 — Text-editing engine

This is the deep one. The content area — the thing the user actually types into — is 70% of the app's feel, and the engine choice determines what's easy, what's hard, and what's impossible.

### Alternatives considered

| Option | Native feel (content area) | Live-render WYSIWYG feasibility | Ramp cost | Cross-OS architecture transfer |
|---|---|---|---|---|
| **TextKit 2** (modern AppKit text system) | Highest | Feasible; TextKit 2 was rewritten for this kind of editor | Medium-high | Architecture lessons transfer to WinUI's RichEditBox / GTK's TextView; implementations don't |
| TextKit 1 | High | Feasible but harder; TextKit 1 was not designed for this | High | Less transferable |
| SwiftUI `TextEditor` | Medium | Too limited; it's a thin NSTextView wrapper | Low | Not meaningful — too thin to generalize |
| WKWebView + CodeMirror 6 | Low-medium (web inside a native shell) | Proven; Obsidian uses CodeMirror | Low | Tempting but the "architecture lesson" becomes "use CodeMirror again" — erodes the native-per-OS argument |
| WKWebView + ProseMirror | Low-medium | Proven; the richer editor web framework | Low | Same as CodeMirror |
| WKWebView + Lexical | Low-medium | Proven; Meta's framework | Low | Same |
| Custom CoreText renderer (Zed-style) | Highest | Feasible but enormous | Very high | Transfers as a design philosophy, not code |

### Recommendation: TextKit 2

> **Validated by D1 (2026-04-22).** The TextKit 2 feasibility spike produced a green recommendation. See `docs/current_work/stepwise_results/d01_textkit2_live_render_spike_COMPLETE.md`. The attribute-based collapse/reveal mechanism works; all behaviors required by the vision are reachable; the five findings surfaced are renderer-level bugs and design gaps, not TextKit 2 limitations. No pivot needed.

**Why.** TextKit 2 was specifically rebuilt to make live-rendering editors like this tractable on Apple platforms — exactly the job we need done. It gives us:

- Proper native text rendering (kerning, ligatures, font fallback, international scripts, RTL) without fighting the browser.
- First-class accessibility (VoiceOver reads our content correctly by construction, not after a retrofit).
- Native selection, cursor, marked-text / input methods, services menu, and find-bar behaviors — all the things that make users think "this feels like a real app" without anyone being able to point to why.
- A viewport-layout-manager model that makes live-render WYSIWYG (render `**foo**` as **foo** inline while cursor-on-line reveals syntax) architecturally cleaner than it would be in TextKit 1.

**Why not a WKWebView-embedded web editor.** It's the pragmatic shortcut and it would get a v1 shipped faster. But it compromises three things that matter to this product specifically:

1. **Native feel of the 70%.** The moment your content area is a webview, your scrolling, text selection, context menu, and subtle typography diverge from the rest of the app. Users can feel it even if they can't name it. Bear and iA Writer went to TextKit for exactly this reason.
2. **Architecture transfer.** Vision Principle 2 says the *shared* layer is design and architecture artifacts; the implementation translates. If md-editor-mac uses CodeMirror-in-a-webview, the design artifact for Windows will say "use CodeMirror-in-a-webview on WinUI" and the native story for Windows collapses into "native shell around a web editor." That's not the product we said we were building. TextKit 2 forces us to make the live-render editor work in a platform's native text system, which produces lessons that actually transfer when we face WinUI's RichEditBox or GTK's GtkSourceView.
3. **Accessibility.** Native text systems get AX labeling for free. Webview-embedded editors require deliberate investment to match, and most don't (Obsidian's AX story is a known weak point).

**What about velocity?** The honest tradeoff is: TextKit 2 costs more calendar time in v1. We mitigate it by (a) using `swift-markdown` for parsing so we're not also building an AST, (b) starting with a source-visible editor and layering live-render behavior in staged increments, (c) accepting that some "delighter" features ship in v2.

**What about TextKit 1.** Lots of existing mac text editors are still on TextKit 1. For a new project targeting macOS 14+ there's no reason to start there. TextKit 2 is the forward path.

---

## Axis 3 — Markdown parsing library

### Alternatives considered

| Option | Provenance | License | CommonMark / GFM | Editor-AST friendly | Status |
|---|---|---|---|---|---|
| **swift-markdown** | Apple | Apache-2 | CommonMark + some extensions | Yes (produces visitable AST) | Actively maintained |
| cmark-gfm (C, via Swift binding) | GitHub | BSD | CommonMark + GFM | Yes | Battle-tested; GitHub's renderer |
| Down (Swift wrapper on cmark) | Community | MIT | CommonMark | Yes | Maintenance slowed; Apple's lib is newer |
| MarkdownUI | Community | MIT | Rendering-focused | Mostly rendering, not bidirectional | Useful as rendering reference, not as our parser |
| Roll our own | — | — | — | — | No |

### Recommendation: swift-markdown as primary, with cmark-gfm as fallback for GFM edge cases

**Why.** swift-markdown is Apple's own library, Swift-native, Apache-licensed, produces a visitor-friendly AST that fits how we'll want to render incrementally. Its CommonMark coverage is solid. Where GFM features (tables, task lists, strikethrough) are needed and swift-markdown lags, we can fall through to cmark-gfm for those nodes — or contribute upstream. Don't roll our own; this is a well-solved problem.

**A note on "rendering" vs. "parsing."** The parser gives us a tree; the *rendering* (turning that tree into the attributed string / layout in TextKit 2) is ours to write. That's where the interesting product work lives. Keeping parsing as a library dependency frees our effort for the rendering layer.

---

## Axis 4 — File-system access and watching

### Alternatives considered

| Option | Latency | Overhead | Sandbox-compatible | Complexity |
|---|---|---|---|---|
| **FSEvents (NSFilePresenter / DispatchSourceFileSystemObject)** | Low | Low | Yes | Low |
| NSMetadataQuery (Spotlight-backed) | Medium | Medium | Yes | Medium |
| Polling `stat` on open files | High | Low at low fan-out | Yes | Very low |
| Kqueue directly | Lowest | Lowest | Yes | High |

### Recommendation: FSEvents via NSFilePresenter for open documents; DispatchSourceFileSystemObject for the folder tree

**Why.** NSFilePresenter is the Apple-blessed way to be notified when a file the app has open changes. It handles coordinated reads and writes correctly (which we'll need for Level 2 agent-aware handoffs) and integrates with the document architecture. For the folder-tree sidebar, a lighter DispatchSourceFileSystemObject (or the folder-level FSEvents API) watches directories without holding per-file presenters open.

**Sandbox compatibility.** Both are sandbox-compatible, which matters because we want Mac App Store distribution on the roadmap as a PortableMind-connected upsell funnel (see distribution axis below). Architecting toward sandbox now is cheaper than retrofitting later.

---

## Axis 5 — Packaging, signing, and updates

### Recommendation

| Concern | Choice | Reason |
|---|---|---|
| **v1 distribution** | Direct download (DMG or ZIP) with Developer ID + notarization | Fastest path to shipping. No App Store review loop. Users can run it without fighting Gatekeeper. |
| **Updates** | Sparkle (EdDSA-signed appcast) | De facto standard for indie mac apps. Ships new versions with one-click update. |
| **Signing identity** | Developer ID Application | Gatekeeper-friendly; required for notarization. |
| **Bundle identifier** | `ai.portablemind.md-editor` (or similar, under the PortableMind reverse-DNS) | Aligns with the PortableMind positioning; stable across future Windows / Linux bundles by varying only the suffix. |
| **App Store (later)** | Sandbox-compatible architecture from day one; App Store build as a separate target gated behind PortableMind tenant sign-in as the upsell | Vision: App Store is the funnel from standalone to connected. We don't ship it in v1, but we don't architect ourselves out of it. |
| **Auto-launch / background** | Not in v1 | md-editor is a foreground app, not a menu-bar utility. |

---

## The committed stack

Pulling the axes together, md-editor-mac v1 will be built as:

- **Language:** Swift (latest stable at implementation start)
- **UI framework:** SwiftUI primary, AppKit via `NSViewRepresentable` where needed (text services, printing, some menus)
- **Text-editing engine:** TextKit 2, with `NSTextView` as the bridging surface where SwiftUI views need to host text
- **Markdown parser:** swift-markdown (Apple), with cmark-gfm as a supplementary option for GFM-specific nodes
- **File watching:** NSFilePresenter for open documents, DispatchSourceFileSystemObject for folder trees
- **Packaging:** direct-download DMG with Developer ID + notarization
- **Updates:** Sparkle with EdDSA-signed appcast
- **Target macOS:** latest two major releases at implementation start (currently macOS 14 Sonoma and macOS 15 Sequoia)
- **Minimum macOS:** one below that (currently macOS 13 Ventura), unless a TextKit 2 feature we rely on forces a higher floor — to be verified during spec work
- **Architecture-for-sandbox:** designed to be sandbox-compatible from day one, even though v1 ships outside the App Store

## Explicitly *not* using

For the record — these are the things a reasonable person might assume we'd reach for but we're deliberately avoiding:

- **Electron.** Vision-level rejection.
- **React Native / Flutter / Tauri.** Same. Cross-platform frameworks produce non-native feel; our positioning is native.
- **Web editor in a WKWebView** for the content area. The pragmatic shortcut; rejected for the reasons in Axis 2.
- **Our own markdown parser.** Solved problem; don't.
- **Core Data / SwiftData for document storage.** The document *is* the file on disk (plain `.md`). Any local app state (recent folders, window positions, preferences) belongs in `UserDefaults` or a small JSON file, not a database. This keeps the vision's "files on disk, agent-readable" contract honest.
- **iCloud Drive as primary sync.** Per positioning, sync is the user's or PortableMind's job, not ours. We work correctly on an iCloud Drive folder the user happens to choose, but we don't build sync into the app.

---

## Architecture lessons to capture for Windows and Linux

Principle 2 says the shared SDLC artifacts live above the stack. For this to be more than aspirational, we need to be explicit now about what abstractions the mac implementation should expose — so the Windows and Linux docs can say "here's that same abstraction, implemented natively on this OS" instead of "here's a different product."

The abstractions worth writing down during mac v1:

1. **Document-type registry.** A document has a type; the type determines its parser, renderer, toolbar, and validator. Markdown is the first type. On mac this lives as a Swift protocol plus a registry; on Windows it's a C# interface; on Linux it's a Rust trait. The *shape* is shared.
2. **Editor state model.** A finite-state description of what the editor is doing at any moment (idle, typing, rendering, saving, handling external edit, showing diff, submitted). Language-agnostic enum / state diagram — this is pure design artifact.
3. **File-system abstraction.** Open, save, watch-open-file, watch-folder, detect-external-change, reconcile-buffer-with-disk. Each OS has different primitives; the interface is identical.
4. **Submit / Handoff protocol.** How a Submit action manifests on disk (sidecar, git commit, trailing comment) or over the wire (PortableMind status transition). This is a wire-format-and-semantics spec, OS-independent. It's also the spec that has to exist for agents to participate, so it's worth writing early.
5. **Toolbar taxonomy.** The list of toolbar actions, their groupings, their keyboard shortcuts, their accessibility labels. Word/Docs-familiar on every OS, even though the widget implementations differ.
6. **Keyboard shortcut map.** An explicit table of commands → chords. Per-OS variants where conventions differ (e.g., Cmd vs. Ctrl), but the command set is shared.
7. **Accessibility contract.** Every toolbar button has an AX label. Every view honors Dynamic Type / platform equivalent. Reduce Motion / high-contrast honored. The *contract* is shared; the mechanism is per-OS.
8. **Settings schema.** What the user can configure (theme, font, toolbar visibility, keyboard profile). Same schema, per-OS UI.
9. **Localization strings table.** One source of truth, per-OS resource-file generation.

These nine artifacts are what Windows and Linux will start from. Writing them *as we build mac* is the discipline that makes Principle 2 real. If we find ourselves writing the mac code and not being able to extract one of these abstractions cleanly, that's a signal we're coupled too tightly to AppKit — stop and refactor the abstraction.

---

## Open questions for spec phase

1. **Minimum macOS version.** Firm on macOS 13 (Ventura) or push to macOS 14 (Sonoma) if TextKit 2 affordances we want are Sonoma-only? Needs a spike.
2. **Live-render staging.** Do we ship v1 with a toggleable source/live-render view (iA Writer pattern), full live-render from day one (Typora / Bear pattern), or Obsidian's cursor-on-line hybrid? Q1 in the competitive-analysis scoping list.
3. **How "toolbar" is implemented.** A SwiftUI `HStack` of `Button`s styled as a toolbar, or an actual `NSToolbar` hosted from AppKit? Impacts look-and-feel-vs-flexibility tradeoff.
4. **Document model.** A single `MarkdownDocument` type in v1, or start the document-type registry abstraction from day one (Principle 3)? Costs a bit of upfront architecture but makes the second document type much cheaper to add.
5. **PortableMind connectivity layer.** Where does the MCP / API client live — in the app directly, or as a separate Swift package we can potentially reuse for a future CLI or Windows port? Probably a package, but worth confirming.
6. **Which TextKit 2 examples to lean on.** Apple's sample code (WWDC 22 "What's new in TextKit") is a starting point; real-world Swift OSS is thinner. Worth a pre-spec spike to confirm feasibility of our live-render approach.

Each of these is the right scope for a spec doc, not this one.
