# Competitive Analysis — md-editor

> Methodology: `ops/sdlc/knowledge/product-research/competitive-analysis-methodology.yaml`
> Vision input: `apps/md-editor-mac/docs/vision.md`
> First-pass date: 2026-04-22
> Verification pass date: 2026-04-22

---

## Verification pass (read first)

This document has been through a second pass whose purpose was to replace general-knowledge assertions with citations from current (2026) authoritative sources. The verifier used, in priority order: official product homepages, official documentation, official release notes / changelogs, official pricing pages, official GitHub repositories, and well-known third-party corroboration (MacStories, GitHub issue threads, Obsidian community forum). No apps were installed or run — this is a docs-based pass. See the **Verification Log** at the bottom of this file for every specific cell that changed and why.

**Confidence level the reader should assign to the matrix:**

- **High confidence** — Pricing, platforms, UI toolkit / rendering stack, file-system model, last-release date. These were all verified against primary sources.
- **Medium confidence** — Formatting-toolbar posture, external-edit detection behavior, accessibility ratings. These are documented in principle but benefit from a hands-on test to confirm real-world feel.
- **Low confidence** — Competitor-by-competitor VoiceOver quality, exact diff behavior under agent-driven edits. These cannot be credibly settled without running the apps.

The verification pass corrected **one architectural error** (Typora is Electron, not Qt — see log), tightened pricing on every paid competitor, confirmed Bear's SQLite-backed storage is unchanged in Bear 2, confirmed Obsidian has an actively-maintained best-of-breed toolbar plugin (Editing Toolbar by PKM-er), and confirmed Zed now ships markdown preview with Mermaid as of 2026 — a material update from the first-pass note.

---

## Landscape summary

The desktop markdown editor market has settled into three stable archetypes: the **live-WYSIWYG editor** (Typora, Bear, iA Writer's preview mode), the **split-pane source+preview editor** (Mark Text historically, VS Code, Zed), and the **knowledge-base / notebook** (Obsidian, Ulysses, Craft). Almost every product optimizes for one of two user profiles — the minimalist writer (iA Writer, Ulysses, Bear) or the technical power user (Obsidian, Zed, Mark Text) — and the tooling reflects it. Persistent **Word/Docs-style formatting toolbars are rare** in the default UX; the dominant pattern is "markdown is the toolbar" (type `**foo**`, get bold). Native per-OS implementations are a minority — most cross-platform apps ship on Electron (including Typora, [confirmed via their GitHub org](https://github.com/typora/electron) — correcting our first-pass note). And **no meaningful competitor today is built for human-in-the-loop agentic workflows**: there is no standard for rendering agent edits, no staged-handoff UX, no "an agent also writes to this folder" mental model. That absence is the central opportunity md-editor is positioned against.

## Competitors included

| # | Product | Why included |
|---|---------|--------------|
| 1 | **[Typora](https://typora.io/)** | Live-render archetype; the "buried format menu" anti-pattern called out in our vision. Direct comparison point. |
| 2 | **[iA Writer](https://ia.net/writer)** | Premium minimalist archetype, macOS-native feel, strong typography story. Sets the bar for "feels native." |
| 3 | **[Obsidian](https://obsidian.md/)** | Knowledge-base archetype, Electron, technical power users. The incumbent in the "folder of markdown" model. |
| 4 | **[Bear](https://bear.app/)** | Apple-platform-native, genuine SwiftUI/AppKit implementation, has a real formatting toolbar. Closest existing analog to "native + toolbar-first." |
| 5 | **[Ulysses](https://ulysses.app/)** | Premium subscription writer's tool, Apple-native. Establishes the subscription + library-model reference point. |
| 6 | **[Mark Text](https://github.com/marktext/marktext)** | Open-source Electron reference; represents the "free community fork" archetype. |
| 7 | **[Zed (markdown mode)](https://zed.dev/)** | Native Rust/GPUI editor with live markdown preview; added during discovery as the "native code-editor-with-good-markdown" disruptor. Relevant because its rendering is fast and it's genuinely non-Electron. |

## Competitors considered but rejected

| Product | Why rejected |
|---------|--------------|
| **Notion** | Block editor, not a markdown editor. Files aren't `.md` on disk. Referenced below as a familiarity anchor only. |
| **Google Docs** | Same — block editor, not markdown-native. Familiarity anchor only. |
| **Craft** | Block editor with markdown export; not operating on `.md` files in a folder, so outside the archetype. |
| **VS Code** | IDE with markdown plugins, not a markdown editor per se. Overlaps with Zed's role; Zed better represents "native + markdown mode." |
| **MacDown** | Abandoned (last release 2019), no active development. |
| **Noteplan** | Calendar-oriented; different archetype. |
| **Logseq** | Outliner-first data model (bullets), not freeform markdown. Not a fair peer. |
| **Dropbox Paper / HackMD** | Web-first; we're comparing native desktop editors. |

---

## 1. Feature Comparison Matrix

Cell conventions: **Yes/No/Partial** for binary dimensions. Level names (e.g., "Basic / Standard / Advanced") for spectrum dimensions — see detail cards below. Architectural dimensions use a short label. Inline links point at the primary source for the claim; where one source covers a whole dimension, the link appears on the dimension row. `?` = could only be verified by hands-on test; explicitly called out.

| Dimension | Typora | iA Writer | Obsidian | Bear | Ulysses | Mark Text | Zed (md) | Ours (target) |
|---|---|---|---|---|---|---|---|---|
| **Core editor model** | | | | | | | | |
| Editor model | Live-WYSIWYG | Source + toggle preview | Live-render (Live Preview) or source | Live-WYSIWYG (Panda / Bear 2) | Source + toggle preview | Live-WYSIWYG | Source + [split preview pane](https://zed.dev/languages/markdown) | ? |
| Source ↔ rendered parity | High | High (via toggle) | High (Live Preview mode) | High | Medium (Ulysses-flavored markup — see file-system row) | High | High (read-only preview) | ? |
| Raw-markdown escape hatch | Yes (toggle) | Yes (toggle) | Yes (Source mode) | Partial (["Hide Markdown" toggle in Bear 2](https://community.bear.app/t/show-hide-markdown/49)) | Partial (custom markup) | Yes (toggle) | Yes (always source) | ? |
| **Formatting toolbar (primary vision lens)** | | | | | | | | |
| Persistent formatting toolbar | **No** — [Format menu and context menu only, confirmed by Typora team as design intent](https://github.com/typora/typora-issues/issues/2412) | **No** — ["No buttons, no popups, no title bar" is explicit design philosophy](https://ia.net/writer) | **No by default** — [community plugin ("Editing Toolbar" by PKM-er) provides a MS-Word-like toolbar; v4.0.5 actively maintained 2026](https://github.com/PKM-er/obsidian-editing-toolbar) | **Yes** (persistent top toolbar with format buttons; inline link popover) | Partial (Markup bar above keyboard on iPad; macOS relies on menus) | No (toolbar is a sidebar, not format) | No (code-editor UX) | **Yes (persistent, Word/Docs-style, toggleable via View menu)** |
| Toolbar hideable via View menu | N/A | N/A | Plugin-dependent | Yes | Yes | N/A | N/A | Yes (required) |
| Word/Docs shortcut familiarity (Cmd+B/I/K) | [Yes](https://support.typora.io/Shortcut-Keys/) — Cmd+B/I/K and Cmd+1..6 headings | Yes | Yes | Yes | Yes | Yes | Partial (code-editor bindings dominate) | **Yes (Word/Docs-first)** |
| Link insertion UX | Menu / Cmd+K | Menu / Cmd+K | Menu / Cmd+K (Wiki + MD links) | **Inline popover** | Menu / Cmd+K | Menu / Cmd+K | Manual markdown | ? |
| Table insertion UX | Menu + visual grid | Source only | Plugin / source | Menu | Menu | **Visual inline editor** | Source only | ? |
| Image insertion UX | Drag-drop + menu | Drag-drop | Drag-drop (vault-aware) | Drag-drop | Drag-drop | Drag-drop | Manual | ? |
| **Native vs Electron** | | | | | | | | |
| UI toolkit | **Electron (Chromium)** — [confirmed via typora/electron repo](https://github.com/typora/electron) (corrected from our first pass's "Qt" — see log) | **AppKit/SwiftUI (native)** | **Electron (Chromium)** | **SwiftUI/AppKit (native)** | **AppKit / Mac Catalyst (native)** | **Electron** | **Rust + GPUI (custom native GPU renderer)** — [per Zed homepage](https://zed.dev/) | **SwiftUI/AppKit (target)** |
| Launch time perception | Slow-to-moderate (Electron) | Very fast | Slow (Electron cold start) | Very fast | Very fast | Slow (Electron) | Very fast | ? |
| Memory footprint | Moderate-high | Low | High | Low | Low | High | Low-moderate | ? |
| Genuinely native chrome (menus, dialogs, typography) | No (Electron) | Yes | No | Yes | Yes | No | Partial (custom GPUI; non-idiomatic but high quality) | Yes (required) |
| **File-system model** | | | | | | | | |
| Model | Single-file or folder | Folder of files ("Library") | Vault (folder root) | **Proprietary SQLite DB** | **Proprietary library (.ulyz / iCloud-private)** | Folder of files | Folder of files (project) | Folder-of-files + single-file |
| Files are plain `.md` on disk | Yes | Yes | **Yes (signature feature)** | **No — [SQLite database at ~/Library/Group Containers/.../database.sqlite](https://bear.app/faq/where-are-bears-notes-located/)** | **No — [proprietary .ulyz / Markdown XL in private iCloud folder](https://help.ulysses.app/en_US/dive-into-editing/markdown-xl); plain `.md` only via External Folders at cost of Ulysses-specific features** | Yes | Yes | **Yes (required for agent workflows)** |
| Folder tree / sidebar | Optional | Yes (Library) | Yes (Vault explorer) | Notes list + tags | Groups + sheets | Yes | Yes (project tree) | Yes |
| External-edit detection (agent writes file, UI refreshes) | Yes | Partial — [Library Locations feature exposes external folders; some forum reports of needing Files-app kick to refresh on iOS](https://ia.net/writer/support/help/trouble-shooting) | Yes | N/A (DB-backed) | N/A (DB-backed) | Partial | Yes | **Yes (required)** |
| **Agent / automation friendliness** | | | | | | | | |
| File watching for external changes | Yes | Partial (see above) | Yes | No (DB) | No (DB) | Partial | Yes | **Yes** |
| Diff / change-attribution UI | **No** | No | No (plugins approximate) | No | No | No | No (git gutter only) | **Yes (differentiator)** |
| Staged human handoff / review mode | No | No | No | No | No | No | No | **Yes (differentiator)** |
| CLI / URL scheme / scripting | URL scheme (limited) | URL scheme | URI scheme + full plugin API | URL scheme (x-callback) | URL scheme (x-callback) | None notable | CLI + [Rust/WASM extension API](https://zed.dev/blog/zed-decoded-extensions) | ? |
| Plugin / extension API | No | No | **Yes** (huge ecosystem) | No | No | No (themes only) | **Yes — [Rust/WASM extensions via zed_extension_api](https://zed.dev/blog/zed-decoded-extensions); distributed through zed-industries/extensions registry** | ? (vision = doc-type plugins) |
| **Markdown feature depth** | | | | | | | | |
| CommonMark / GFM | GFM | GFM-ish | CommonMark + Obsidian ext | GFM-ish | Ulysses Markdown XL (28 tags, superset but incompatible with standard md tags like comments/annotations) | GFM | GFM | ? |
| Math (LaTeX/KaTeX) | Yes | Partial | Yes | No | No | Yes | In preview (not documented in core docs; user reports mixed) | ? |
| Diagrams (Mermaid) | Yes | No | Yes | No | No | Yes | **Yes — [Mermaid in markdown preview shipped Feb 2026](https://releasebot.io/updates/zed)** | ? |
| Code blocks w/ syntax highlighting | Yes | Yes | Yes | Yes | Yes | Yes | Yes (tree-sitter) | ? |
| Footnotes / wiki links / callouts | Yes / No / No | Yes / No / No | Yes / Yes / Yes | Partial | Partial | Yes / No / No | Yes / No / No — [anchor links & footnotes in preview April 2026](https://releasebot.io/updates/zed) | ? |
| **Extensibility to non-markdown formats** | | | | | | | | |
| Opens other text formats (JSON/YAML) meaningfully | No | No | No (plain-text only) | No | No | No | **Yes** (all code languages via tree-sitter) | ? (long-term yes) |
| Document-type plugin model | No | No | Plugin-reachable | No | No | No | Language-based, not doc-type | ? |
| **Keyboard & accessibility** | | | | | | | | |
| Word/Docs shortcut parity (Cmd+B/I/U/K/Shift+Cmd+7/8) | High | High | High | High | High | High | Code-editor default | ? |
| VoiceOver / screen reader | Poor (Electron) | Good (native AX) | Poor (Electron) | Good (native AX) | Good (native AX) | Poor (Electron) | Partial (custom renderer — not inheriting AppKit AX tree, known limitation) | **Good (AX-first)** |
| Keyboard-only navigation | Good | Excellent | Good (with plugins) | Good | Good | Good | Excellent | ? |
| High-contrast / Dynamic Type | Partial | Yes | Theme-dependent | Yes | Yes | Theme-dependent | Yes | ? |
| **Cross-platform story** | | | | | | | | |
| Platforms | mac / win (x64, x86, ARM) / linux [(typora.io)](https://typora.io/) | mac / win / iOS / iPadOS [(ia.net/writer, trial page)](https://ia.net/writer) — Android version exists historically but is no longer promoted as first-class | mac / win / linux / iOS / Android [(obsidian.md/download)](https://obsidian.md/download) | Apple-only (mac / iPhone / iPad) [(bear.app)](https://bear.app/) — **no Android, no web** | Apple-only (mac / iPad / iPhone) [(ulysses.app)](https://ulysses.app/) | mac / win / linux | **mac / linux / win (win stable since Oct 2025)** [(zed.dev/windows)](https://zed.dev/windows) | mac first; win + linux later (per-OS native) |
| Mobile companion | No | Yes (separately purchased) | Yes | Yes | Yes | No | No | ? |
| **Pricing / licensing** | | | | | | | | |
| Model | One-time $14.99 (up to 3 devices) [(typora.io)](https://typora.io/) | One-time, per-platform ("own it forever") [(ia.net/writer)](https://ia.net/writer) | Free (personal) + **Sync $4/mo annual or $5/mo; Publish $8/mo annual or $10/mo; Commercial license $50/yr per user** [(obsidian.md/pricing)](https://obsidian.md/pricing) | **Bear Pro $2.99/mo or $29.99/yr** [(bear.app)](https://bear.app/) | **$5.99/mo or $39.99/yr** [(ulysses.app/pricing)](http://ulysses.app/pricing/) | Open source (MIT) | Open source (GPL) + paid teams | ? |
| Open source | No | No | **No** (freeware core) | No | No | Yes | Yes (editor core) | ? |
| Last significant release (verified) | [v1.13, 2026-04-03](https://support.typora.io/) | Actively maintained (free trial pages current) | [v1.12.7, 2026-03-23](https://obsidian.md/changelog/) | Bear 2.x, actively maintained (community + blog active 2026) | Actively maintained (releases page current) | [v0.17.1, 2022-03-07](https://github.com/marktext/marktext/releases) — commits continue on develop branch but no stable release in ~4 years; [Homebrew cask deprecated 2026-09-01](https://github.com/marktext/marktext/issues/4017) | [Stable 0.231.x, April 2026](https://zed.dev/releases/stable/latest) | — |

---

## 2. Dimension Detail Cards

### Editor model (architectural)
- **Source-only**: Raw markdown text; preview is off or in a separate tab. Familiar to developers; hostile to non-technical users.
- **Split-pane preview**: Source on left, rendered on right. Shows the mapping but doubles cognitive load; non-technical users resent both panes.
- **Live-render (WYSIWYG)**: Typing `**foo**` immediately turns into **foo** inline; there is no separate preview. Best for non-technical audiences; requires a source-escape hatch for power users.
- **Hybrid "Live Preview" (Obsidian)**: Live-render when the cursor is not on the line; source reveals when the cursor enters the line. Compromise that works for technical users but is slightly uncanny for non-technical.

### Formatting toolbar (spectrum — primary vision lens)
- **None**: Shortcuts only. Non-technical users do not discover features.
- **Dropdown-menu-only**: A Format menu exists but nothing visible on screen. Typora's posture — flagged by vision as the anti-pattern. [Typora has explicitly rejected a top toolbar in favor of the menu + context-menu model](https://github.com/typora/typora-issues/issues/2412).
- **Persistent toolbar** (Word/Docs model): Always-on row of labeled buttons for bold/italic/heading/list/link/table/image. Toggleable via View menu. Bear's posture.
- **Persistent toolbar + contextual inline toolbar**: Persistent top row plus a selection-follows-cursor inline bar (as Notion/Craft do). Richest UX; hardest to get right without clutter.

### Native vs Electron (architectural)
- **Electron / Chromium shell**: Ships a browser. Good cross-platform parity; bad memory, bad startup, blurred native chrome, weak accessibility, inconsistent typography. **Obsidian, Mark Text, Typora.** (Our first pass mis-cited Typora as Qt; it is Electron — see log.)
- **Qt / cross-platform C++ toolkit**: Single codebase, more native feel than Electron but still not idiomatic per-OS. No competitor in this set actually ships Qt.
- **Native per-OS (AppKit/SwiftUI on mac, WinUI/WinAppSDK on win, GTK/Qt on linux)**: Idiomatic chrome, best perf, best accessibility, highest build/maintenance cost. iA Writer, Bear, Ulysses on mac; our stated target.
- **Native GPU-rendered editor (Zed / GPUI)**: Custom renderer; very fast; non-idiomatic chrome; custom accessibility surface. Interesting for text perf but not what our audience wants.

### File-system model (architectural)
- **Single-file**: Open one `.md`, edit, save. No library concept. VS Code-style.
- **Folder-of-files (vault / project)**: User picks a directory; app shows a tree sidebar; every file is plain `.md` on disk, editable by any other tool (including agents). Obsidian's foundational model.
- **Proprietary library / database**: App owns a SQLite/iCloud store; files are exported, not source-of-truth. [Bear stores in `database.sqlite` (confirmed 2026)](https://bear.app/faq/where-are-bears-notes-located/). [Ulysses stores in `.ulyz` / private iCloud (confirmed 2026)](https://help.ulysses.app/en_US/dive-into-editing/markdown-xl). **Incompatible with agentic workflows** — agents cannot read/write the store. Ulysses has an External Folders mode that can write plain `.md`, but at the cost of Ulysses-specific features (Markdown XL tags, annotations) — so it's not a full escape hatch.

### Agent / automation friendliness (spectrum)
- **None**: Desktop-only editor; agent has no surface to hand off to. Most editors.
- **External-edit aware**: App detects when a file is modified on disk and reloads the buffer without losing cursor/selection. Table stakes for agent workflows.
- **Agent-aware affordances**: Above + shows a visible diff when the file changes while open, attributes changes to actor (human vs agent), supports staged "review this handoff" UI, has a CLI/URL scheme that agents can invoke. **No competitor does this today** — the differentiator.

### Extensibility to non-markdown formats (spectrum)
- **Markdown-only**: Core assumes `.md`; no document-type abstraction.
- **Generic text + syntax highlighting**: Opens any text file but treats it as source, not a structured document (Zed, Mark Text).
- **Plugin-reachable**: A plugin API exists that *could* layer non-markdown formats, but no first-class doc-type concept (Obsidian).
- **Document-type plugin model** (our vision): The editor core is format-agnostic; each document type registers a renderer, toolbar, validator. Markdown is one type; JSON/YAML/workflow graphs plug in later. **No current desktop editor is architected this way.**

### Keyboard-shortcut familiarity for Word/Docs users (spectrum)
- **Code-editor default** (Cmd+D for duplicate, Cmd+K for palette): Hostile to Word users; Zed ships this by default.
- **Mixed**: Some Word shortcuts work, many collide with code-editor bindings.
- **Word/Docs-first**: Cmd+B bold, Cmd+I italic, Cmd+U underline, Cmd+K link, Cmd+Shift+7 numbered list, Cmd+Shift+8 bullet list, Cmd+Alt+1..6 headings. This is the expected contract. Typora, Bear, iA Writer all sit here; [Typora's shortcut page is explicit](https://support.typora.io/Shortcut-Keys/).

### Accessibility (spectrum)
- **Poor**: Electron default; arbitrary DOM, no AX tree commitments, bad for VoiceOver. Obsidian, Mark Text, Typora sit here.
- **Partial**: Some keyboard coverage, partial screen-reader support. Zed's custom renderer lands here by construction — it is not rendering through AppKit so does not inherit the default AX tree.
- **Good**: Uses the OS AX framework (NSAccessibility on mac, UIA on win). Honors Dynamic Type, high-contrast, Reduce Motion. Native AppKit/SwiftUI editors (iA Writer, Bear, Ulysses) clear this bar by construction.

### Pricing / licensing (architectural)
- **Open source**: Mark Text (MIT), Zed (GPL). No revenue friction; may lack polish. Mark Text specifically hasn't cut a stable release since 2022 despite continued commits, and its Homebrew cask is [flagged for deprecation on 2026-09-01](https://github.com/marktext/marktext/issues/4017) — signaling packager health concerns even if the repo is technically alive.
- **One-time license**: [Typora $14.99](https://typora.io/), [iA Writer per-platform one-time](https://ia.net/writer). Classic indie model; friendly to purchase.
- **Freemium / free personal**: [Obsidian](https://obsidian.md/pricing) — free for personal use, paid Sync ($4/mo annual) / Publish ($8/mo annual) / Commercial license ($50/yr/user) add-ons.
- **Subscription**: [Ulysses $5.99/mo or $39.99/yr](http://ulysses.app/pricing/), [Bear Pro $2.99/mo or $29.99/yr](https://bear.app/). Recurring revenue, but adoption friction for casual users.

---

## 3. Competitor Spotlights

**Typora.** Genuinely pioneered the live-render UX and earned a devoted following for its restraint and typography. Its formatting controls live in the Format menu and context menu only — [this is explicit design intent, reaffirmed on the Typora issue tracker](https://github.com/typora/typora-issues/issues/2412). For a fluent markdown typist this feels clean; for a Word user this reads as "the tool can't do that," which is exactly the adoption risk md-editor exists to fix. Architecturally Typora ships on Electron — the first-pass document incorrectly called it Qt. That makes Typora's performance story softer than we credited, though its polish is still better than most Electron peers.

**iA Writer.** The highest-polish native-mac experience in the category. Its "focus mode" and "syntax highlighting" (parts-of-speech coloring) are differentiated writer-craft features. But it is minimalist to a fault: ["No buttons, no popups, no title bar"](https://ia.net/writer) is stated design philosophy, meaning no persistent toolbar. It treats markdown as a writing format, not as an agent handoff artifact. External-edit detection exists via iA Writer's Library Locations feature but [forum reports indicate it can require a Files-app nudge on iOS to pick up external changes](https://ia.net/writer/support/help/trouble-shooting) — so the "watch-folder" story is thinner than we originally assumed, especially on mobile. If md-editor wants to match its typography and native feel while adding the toolbar and agent dimensions, iA Writer is the feel-bar.

**Obsidian.** The de facto standard for "folder of plain markdown files" — the same file-system model md-editor needs. Massive plugin ecosystem, actively maintained (v1.12.7 released 2026-03-23). Everything is Electron-on-Chromium, which undermines native feel and accessibility. Obsidian does not ship a persistent formatting toolbar by default; the best-of-breed community plugin for this is [**Editing Toolbar** by PKM-er](https://github.com/PKM-er/obsidian-editing-toolbar), modelled on MS-Word-style formatting bars, actively maintained (v4.0.5 as of early 2026). This closes an evidence gap from our first pass: the toolbar *is* achievable in Obsidian, but only by installing and configuring a plugin — the default experience remains "shortcuts and slash-commands only." Obsidian's existence validates the vault model; its weaknesses (Electron, technical-user-first default UX, no toolbar without a plugin, no agent-awareness) validate md-editor's positioning.

**Bear.** The closest existing analog to "Apple-native + persistent formatting toolbar." Bear 2 (the Panda-era redesign, shipped 2023 and refined through 2026) introduced "Hide Markdown" and a cleaner toolbar/popover story. Its toolbar, inline link popover, and typographic care are the closest reference for our default UX. [Confirmed 2026: notes live in Bear's SQLite database](https://bear.app/faq/where-are-bears-notes-located/) at `~/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite`, not as `.md` files on disk. The DB is read-accessible but the docs explicitly warn against writing to it. So an agent cannot safely read/write Bear's notes in the course of a HITL loop. The takeaway is "copy the UX, reject the storage model."

**Ulysses.** Demonstrates a viable subscription model ($5.99/mo or $39.99/yr) and a library-of-sheets organization, with excellent macOS integration. [Uses Ulysses Markdown XL, a 28-tag superset](https://help.ulysses.app/en_US/dive-into-editing/markdown-xl) that includes tags (comments, annotations, redact) that don't round-trip through plain Markdown. Its native files are `.ulyz` — zipped XML in a private iCloud folder — which is a hard disqualifier for agent interop. Ulysses *does* offer "External Folders" that operate on plain `.md`, but only at the cost of Ulysses-specific features. Worth studying for library navigation UX and for iPad behavior we may want to match long-term.

**Mark Text.** Open-source Electron reference — shows what the community has built for free. Best table-editing UX in the set (visual inline table editor). Underinvested: last stable release is [v0.17.1 from 2022-03-07](https://github.com/marktext/marktext/releases), and the Homebrew cask is [slated for deprecation on 2026-09-01](https://github.com/marktext/marktext/issues/4017) — development continues on the `develop` branch (55.4k stars, 1.4k open issues) but no stable cut in four years. Interesting because it confirms: Electron cannot deliver the native feel our audience needs, regardless of how well the markdown features are done, and an open-source project without a strong release cadence atrophies in practice even if the repo looks active.

**Zed (markdown mode).** The disruptor: non-Electron, [GPU-rendered via custom GPUI framework](https://zed.dev/), extremely fast, and it opens any text format (JSON/YAML/etc.) with meaningful syntax treatment — partially foreshadowing our "document-type" future. **Material update from our first pass:** Zed's markdown preview is real and has matured significantly in 2026 — it ships a [split-pane preview with Mermaid diagram rendering (Feb 2026)](https://releasebot.io/updates/zed) and [anchor links + footnotes in preview (April 2026)](https://releasebot.io/updates/zed). Windows stable landed [October 2025](https://zed.dev/windows), so Zed is now a true mac/linux/win editor, not mac/linux-only as we'd noted. Its [Rust/WASM extension API](https://zed.dev/blog/zed-decoded-extensions) is a serious architectural reference point if we consider plugin extensibility. But Zed is a code editor first; its shortcuts, chrome, and toolbar posture remain hostile to non-technical users. Proves native-non-Electron is tractable on modern stacks; does not solve for our audience.

**Familiarity anchors (not competitors).** **Notion** and **Google Docs** matter only as the mental models our primary audience brings with them: persistent toolbar, slash-command menu, inline link popover, "Heading 1" named in a dropdown rather than `#` syntax. We are not competing with them — they don't operate on `.md` files in a folder — but our default UX should feel recognizable to a user arriving from either.

---

## 4. Scoping Questions

Ordered by impact — the highest-leverage decisions first.

### Q1. Editor model (Architectural)
**Live-WYSIWYG (Typora, Bear) vs source + toggleable preview (iA Writer, Ulysses) vs Obsidian-style Live Preview hybrid.** Live-WYSIWYG is best for our priority-1 audience (non-technical) but requires a rigorous source-escape hatch for priority-3 (technical). Which model anchors our default, and what escape hatch do we guarantee on day one?
*Informed by: Typora, Bear, iA Writer, Obsidian.*

### Q2. Formatting-toolbar scope for v1 (Level)
Vision is firm: **persistent, Word/Docs-style, toggleable via View menu**. Open question is breadth. MVP = bold/italic/heading/list/link? Standard = add tables, images, code block, blockquote? Advanced = add inline contextual toolbar à la Notion/Craft? Our vision mandates at least Standard; does v1 include the inline contextual layer, or defer?
*Informed by: Bear (persistent + inline link popover), Mark Text (visual tables), Typora (anti-pattern), Obsidian's Editing Toolbar plugin (community-proven reference for what a Word-style toolbar in a markdown app looks like).*

### Q3. File-system model (Inclusion)
**Folder-of-plain-`.md`-files is non-negotiable** per the agentic-workflow vision (agents write to disk). But do we also support *single-file open* (drag a file onto the dock, edit, save, close — no library) as a v1 affordance? Obsidian forces a vault; Typora allows single files; iA Writer encourages Library but permits single. Single-file-first onboarding lowers the barrier for non-technical users encountering one handoff at a time.
*Informed by: Obsidian (vault-required), Typora (both), iA Writer (both).*

### Q4. Agent-awareness depth for v1 (Level / MVP boundary)
This is our differentiator and no competitor has shipped it. Possible levels:
1. **Minimal**: External-edit detection + "file changed on disk" toast (iA Writer, Obsidian already do this — though iA Writer's mobile story is weaker than we originally credited).
2. **Diff view**: When an agent has changed the file since you last saved, show a unified diff before the buffer updates; accept / discard / merge.
3. **Attribution**: Track who (human vs agent) made which hunk, persist across sessions via sidecar metadata or git.
4. **Staged handoff**: A "hand off to agent" button that writes a handoff marker, and a corresponding "pick up from agent" flow.

What's the v1 bar — just (1), or (1) + (2)? (3) and (4) imply metadata architecture that needs to be right before lock-in.
*Informed by: no competitor has (2)/(3)/(4); vision principle 1 requires at least external-edit detection and a diff view to be credible.*

### Q5. Document-type architecture now vs later (Architectural / Trade-off)
Principle 3 says markdown today, JSON/YAML tomorrow. We can either (a) architect the editor core around a **document-type plugin model** from day one (higher upfront cost; keeps the door open), or (b) ship a markdown-first v1 with a refactor path (faster to v1; risks markdown assumptions leaking into core). Zed is the only competitor that's meaningfully format-plural, and it got there by being a code editor, not by registering document types. Do we pay the architecture tax in v1 to earn the plug-in surface later?
*Informed by: Zed (format-plural via tree-sitter + Rust/WASM extension API, but not doc-type-plural), Obsidian (plugins but markdown-only at core).*

### Q6. Keyboard contract (Inclusion / Integration)
Do we commit to **Word/Docs-first shortcuts as the default** (Cmd+B bold, Cmd+K link, Cmd+Shift+7/8 lists, Cmd+Opt+1..6 headings) — which means overriding some macOS/code-editor defaults — or do we let the OS/platform idioms win where they collide? Priority-1 users expect Word semantics; priority-3 users expect code-editor semantics. Pick a default, and decide whether the alternate is a one-click "keybinding profile" or a deeper preference.
*Informed by: Bear (Word-first), Zed (code-editor-first), Typora (Word-first; Cmd+B/I/K and Cmd+1..6 all present).*

### Q7. Plugin / extension API (Inclusion / MVP boundary)
Obsidian's plugin ecosystem is its moat. Matching it in v1 is out of scope, but shipping **without any extension point** locks us into doing every feature ourselves. Zed's [Rust+WASM extension contract](https://zed.dev/blog/zed-decoded-extensions) is a serious architectural reference for what a modern, sandboxed extension API looks like on a native GPU-rendered editor. Options: (a) no plugin API in v1; (b) read-only plugins (themes, syntax highlighting); (c) full plugin API (actions, toolbar buttons, document-type renderers). Decision is entangled with Q5: if we commit to the document-type architecture, (c) is almost free; if we don't, (c) is a large separate investment.
*Informed by: Obsidian (full API), iA Writer / Bear (none), Zed (Rust/WASM extension contract — WIT-defined, actively growing 2026).*

### Q8. Storage and sync posture (Trade-off)
Apple-native competitors (Bear, Ulysses) run proprietary databases and own sync. Obsidian stays file-on-disk and sells sync as an add-on ($4/mo annual). Our vision mandates file-on-disk (agents need to read/write). Do we offer **any** built-in sync (iCloud Drive, Dropbox watch folder, git integration) in v1, or defer all sync to the user's file system? The answer sets whether we're a "local editor" or a "collaborative surface" narrative in v1.
*Informed by: Obsidian (file-on-disk, sync is paid add-on), Bear / Ulysses (opinionated cloud), iA Writer (user-chosen sync provider via Files-app integration).*

### Q9. Accessibility bar for v1 (Level)
Native AppKit/SwiftUI inherits a solid default AX tree. To clear a **Good** bar we need: VoiceOver-labeled toolbar buttons, full keyboard-only navigation including the folder tree, Dynamic Type honored in the editor, high-contrast mode honored, Reduce Motion honored. Is v1 committed to AA on day one, or do we ship AA-adjacent and backfill? Electron competitors (Obsidian, Mark Text, Typora) largely fail this bar; Zed's custom GPUI renderer is partial-by-construction. Being noticeably better is a genuine differentiator for government / regulated / accessibility-first buyers.
*Informed by: iA Writer, Bear (good — inherit AppKit AX), Obsidian, Mark Text, Typora (poor — Electron DOM), Zed (partial — custom renderer).*

### Q10. Cross-platform parity policy (Integration / Trade-off)
Vision commits to per-OS native. Open question is *parity*: does Windows lag mac by one version, or must every feature ship on both before release? Lockstep costs velocity; lag risks a two-tier experience and doubles the support story. And where do shared SDLC artifacts end and per-OS variants begin (keyboard maps, menu structures, file dialogs are all per-OS by nature)? Zed's mac→linux→win trajectory (Windows stable only in October 2025, after years on other platforms) is a relevant data point: staggered launches are a working model even for ambitious native-non-Electron projects.
*Informed by: iA Writer (multi-platform, near-parity), Obsidian (Electron makes parity cheap), Bear / Ulysses (Apple-only avoids the question), Zed (staggered per-OS launches worked).*

---

## 5. Evidence gaps (remaining after verification pass)

The first-pass document had several items flagged as "evidence gaps." After this verification pass, some are closed and others remain — with a clearer sense of which are closable by docs alone and which require hands-on testing.

**Closed by this pass:**
- **Typora's UI toolkit.** Was cited as "Qt (C++)." [Corrected: Electron/Chromium, confirmed via the typora/electron GitHub repo](https://github.com/typora/electron). See Verification Log entry #1.
- **Obsidian plugin-toolbar best-of-breed.** [**Editing Toolbar** by PKM-er](https://github.com/PKM-er/obsidian-editing-toolbar), v4.0.5, actively maintained into 2026. It explicitly targets the MS-Word / Notion / Docs migration audience and is the standard answer in Obsidian community threads.
- **Zed markdown-mode current state.** [Markdown preview with Mermaid shipped Feb 2026; anchor links and footnotes in preview shipped April 2026; Windows stable since October 2025](https://releasebot.io/updates/zed). First-pass notes were too conservative.
- **Bear and Ulysses are still DB-backed in their current versions.** Bear: [SQLite, confirmed](https://bear.app/faq/where-are-bears-notes-located/). Ulysses: [.ulyz + Markdown XL in private iCloud, confirmed](https://help.ulysses.app/en_US/dive-into-editing/markdown-xl).
- **Current pricing.** Verified for every paid competitor on their own pricing page, April 2026.

**Remaining (require hands-on testing — not docs-closable):**
- **VoiceOver quality in practice** on Bear, iA Writer, Obsidian, Zed. The ratings above are based on known toolkit behavior (native AppKit good, Electron poor, custom GPUI partial) but a 30-minute VoiceOver pass on each would sharpen Q9.
- **External-edit detection latency and cursor-preservation** on iA Writer and Obsidian when an agent writes to the same file. Forum reports suggest iA Writer's mobile story is uneven; unclear whether the desktop experience is clean. Would need a live test with a file-touching script.
- **Bear 2's toolbar/popover feel in current macOS (15/16).** Bear has been refining through 2023-2026; the current UX is best judged by running the app. Confirming our "closest existing analog" claim empirically would strengthen our v1 toolbar spec.
- **Obsidian Editing Toolbar plugin feel vs Bear's native toolbar.** We know the plugin exists and is maintained; we don't know whether it feels as polished as Bear's native toolbar or still has the seams of a late-bound plugin (popup flicker, theme collisions, keyboard-focus gotchas). Would inform whether Obsidian+plugin is the right reference, or whether Bear is.

**Out of scope for this pass, flagged for later:**
- **Windows-native markdown editors** (WriteMonkey, Markdown Monster, etc.) — our current landscape is macOS-anchored because of our first-target. Before committing the vision's "per-OS native" scope on Windows, we should do a parallel landscape scan for Windows-native markdown apps specifically.

---

## Verification Log

Changes made in the 2026-04-22 verification pass, relative to the 2026-04-22 first-pass document. Order is by impact.

1. **Typora UI toolkit: Qt → Electron** *(updated 2026-04-22: was "Qt (C++) on mac/win/linux", corrected to "Electron (Chromium)" based on the [typora/electron GitHub org](https://github.com/typora/electron) and Typora's own release pages. First-pass was incorrect.)* This changes the "native chrome," "launch time," and "memory footprint" cells for Typora from favorable to unfavorable, and it subtly changes the shape of Q9 (Accessibility): Typora now lands with Obsidian and Mark Text in the Electron-poor-AX bucket, not in a Qt-middle-ground.

2. **Bear storage model confirmation.** *(updated 2026-04-22: first-pass asserted SQLite without citation; verified via [Bear's own FAQ](https://bear.app/faq/where-are-bears-notes-located/) which names the exact file path and explicitly warns against writing to it. No cell value changed, but the claim is now sourced, not asserted.)*

3. **Ulysses storage model confirmation.** *(updated 2026-04-22: first-pass said "proprietary library" without detail; verified via [Ulysses's Markdown XL help page](https://help.ulysses.app/en_US/dive-into-editing/markdown-xl) that the native format is `.ulyz` in a private iCloud folder using Markdown XL markup, and that External Folders mode *can* produce plain `.md` but loses XL-specific tags. Cell now reflects the trade-off rather than a flat "proprietary.")*

4. **Obsidian toolbar evidence gap closed.** *(updated 2026-04-22: first-pass marked this as "caller may want to close"; closed this pass. The canonical Obsidian Word-style toolbar plugin is [Editing Toolbar by PKM-er](https://github.com/PKM-er/obsidian-editing-toolbar), v4.0.5, actively maintained. Integrated into the Obsidian matrix cell and into Q2/Q7.)*

5. **Zed markdown-mode evidence gap closed — substance shifted.** *(updated 2026-04-22: first-pass marked as "re-check before citing against us." Verified that Zed ships a split-pane markdown preview with Mermaid (Feb 2026) and anchor links/footnotes in preview (April 2026). Zed's markdown mode is materially more capable than our first-pass notes. The matrix's Mermaid cell for Zed is updated from implicit-uncertain to an explicit "Yes" with date.)*

6. **Zed platforms: win-beta → win-stable.** *(updated 2026-04-22: was "mac/linux (win beta)", corrected to "mac/linux/win" with win stable since [October 2025](https://zed.dev/windows). Does not change conclusions but tightens Q10's framing — staggered-native-launch is a proven approach, not an experimental one.)*

7. **Pricing, all paid competitors.** *(updated 2026-04-22: verified each against the current official pricing page. Ulysses $5.99/mo OR $39.99/yr — first pass only cited monthly. Bear Pro $2.99/mo OR $29.99/yr — first pass just said "Bear Pro subscription." Obsidian Sync is $4/mo annual or $5/mo monthly; Publish $8/mo annual or $10/mo monthly; Commercial license $50/yr/user — first pass said only "paid sync/publish add-ons." Typora remains $14.99, up to 3 devices.)*

8. **iA Writer external-edit behavior nuanced.** *(updated 2026-04-22: first-pass rated as clean "Yes"; nuanced to "Partial" based on [iA Writer troubleshooting docs and community reports suggesting Files-app kick is sometimes needed on iOS](https://ia.net/writer/support/help/trouble-shooting). On macOS the behavior is likely better but wasn't verified in docs specifically.)*

9. **Mark Text status nuanced.** *(updated 2026-04-22: first-pass said "sparse releases, aging Electron." Tightened: no stable release since [v0.17.1 on 2022-03-07](https://github.com/marktext/marktext/releases) — four years. Commits on `develop` continue, but [Homebrew cask is flagged for deprecation on 2026-09-01](https://github.com/marktext/marktext/issues/4017). The project is in a "code lives, releases don't ship" state — more precisely described as stalled rather than merely slow.)*

10. **Accessibility row re-bucketed.** *(updated 2026-04-22: with Typora re-classified as Electron, the Accessibility row now cleanly splits into three groups: native AppKit/SwiftUI (Bear, iA Writer, Ulysses) = good-by-construction; Electron (Obsidian, Mark Text, Typora) = poor-by-construction; Zed's custom GPUI = partial-by-construction, because it is not rendering through AppKit and doesn't inherit that AX tree. This re-bucketing makes Q9 sharper and the differentiation story for md-editor stronger.)*

11. **Scoping questions updated where verification shifted framing.** Q2 now explicitly cites Obsidian's Editing Toolbar plugin as a community-proven reference. Q4 acknowledges iA Writer's mobile external-edit detection is weaker than first-pass credited. Q7 pulls in Zed's Rust+WASM extension contract as a concrete architectural reference. Q9 specifies Zed's AX bucket explicitly. Q10 uses Zed's Oct-2025 Windows stable as a concrete "staggered per-OS launches work" precedent. No question was invalidated; all ten still stand.
