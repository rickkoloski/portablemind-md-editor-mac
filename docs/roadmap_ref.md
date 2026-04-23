# md-editor-mac Roadmap (informal)

**Type:** Reference — informal planning sketch, not a commitment.
**Status:** Living; extend at the start of each deliverable cycle. Concrete commitments live in `docs/current_work/specs/dNN_*_spec.md` as they get drafted.

## Why this file exists

Rough ordering of planned deliverables so that current work has context for what comes next. **Order and scope can change.** Anything on this list that isn't in `docs/current_work/specs/` hasn't been scoped yet.

## Current ordering (as of 2026-04-22)

| D# | Deliverable | Status |
|---|---|---|
| D1 | TextKit 2 live-render feasibility spike | ✅ Complete — GREEN recommendation |
| D2 | Project scaffolding — promote spike to real project | ✅ Complete — 2026-04-22 |
| D4 | Source-mutation primitives + keyboard bindings (bold / italic / inline code / link / heading 0–6 / bullet / numbered). No UI yet. | ✅ Complete — 2026-04-22 |
| D5 | Formatting toolbar — visible buttons wired to D4's primitives + View → Show/Hide Toolbar | ✅ Complete — 2026-04-22 |
| D6 | Workspace foundation — folder tree sidebar, tabs, multi-file external-edit, CommandSurface + URL scheme + CLI wrapper | ✅ Complete — 2026-04-23 |
| D3 | Packaging — Sparkle + DMG + Developer ID + notarization | **Deferred** — gates on Apple Developer Program renewal (per `memory/md_editor_apple_developer_state.md`) |
| **D7+** | **PortableMind integration** — connected mode, Submit → status transition, document↔entity association, tenant sign-in, MCP adapter as a second caller of CommandSurface | Now unblocked by D6's workspace + CommandSurface primitives |

## Candidates (unscheduled)

Items on the table but not yet ordered. Most will slot into D6+ or later.

- Folder tree / sidebar navigation
- Outline / heading navigator panel
- Submit / Handoff primitive (standalone mode — git commit / sidecar file)
- Multi-document / tabs / window management
- Preferences window
- Dark mode polish
- Second document type (JSON or YAML) — proves Principle 3 and the document-type registry abstraction from D2
- Search within document; search across vault-like folder
- Typography switch (proportional body) — intentionally held back from D2 because it changes product feel
- VoiceOver / accessibility polish beyond the D2 baseline
- macOS Services menu integration, Quick Look, etc.
- Windows and Linux ports — the second implementations from the shared non-code SDLC artifacts per vision Principle 2

## Ordering principles

1. **Standalone product value first** (D1–D5 keep the app useful without any PortableMind dependency).
2. **Packaging before distribution need, not before.** D3 is right-sized at "can install on another mac"; can slip later if no second machine needs it yet.
3. **Invisible plumbing before visible feature** where it makes validation crisper (e.g., D4 mutations before D5 toolbar).
4. **Don't bundle typography changes with scaffolding or infrastructure.** Feel-changes get dedicated deliverables so we can observe their effect cleanly.
5. **Each deliverable traces back to at least one foundation doc** (`vision.md`, `competitive-analysis.md`, `portablemind-positioning.md`, `stack-alternatives.md`, `engineering-standards_ref.md`).

## Change log

- **2026-04-22** — Initial creation. D1 complete; D2 triad drafted; D3–D5 sketched; PortableMind integration positioned post-D5 per CD's direction during D2 spec review.
- **2026-04-22 (later)** — D2 complete. D3 deferred by CD preference ("packaging only when we hit a threshold of vision features, unless it creates technical risk"). D4 (mutation primitives + keyboard bindings) is next; triad drafted. Ordering is now D4 → D5 → D3 → D6+, with D numbers stable (never reused) per SDLC conventions.
- **2026-04-22 (later still)** — D4 complete. 13 mutations working end-to-end via keyboard, uniform toggle semantics, code-block safety, one-step undo. Four findings surfaced during validation, three fixed in-deliverable (untitled buffer live-render, Strong-inside-Heading font, Shift-chord binding semantics); one UX-polish (`[text]()` empty parens) deferred. i18n caveat on keyboard shortcuts noted for later. D5 (formatting toolbar) is next.
- **2026-04-22 (evening)** — D5 complete. Formatting toolbar live with 7 direct buttons + Heading dropdown (Body + H1-H6). View menu → Show/Hide Toolbar (Cmd+Opt+T) with UserDefaults persistence. Three findings resolved in-deliverable: (1) CommandMenu("View") creates duplicates — use CommandGroup(replacing: .toolbar); (2) .toolbar(.hidden, for: .windowToolbar) hides title bar too — use WindowAccessor + NSWindow.toolbar.isVisible; (3) UITest identifier queries on SwiftUI Button+Label return multiple nodes — use `.firstMatch`. Engineering-standards §2.1 refined with the required query shape. Vision Principle 1 (Word/Docs-familiar authoring) now realized at its core level. Roadmap proceeds to D6+ PortableMind integration or the deferred D3 packaging, CD's choice.
