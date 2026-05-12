# md-editor

A native macOS markdown editor, purpose-built to bring non-technical and semi-technical users into LLM agentic human-in-the-loop workflows as first-class participants. The desktop surface for the PortableMind ecosystem.

> Full vision: [`docs/vision.md`](docs/vision.md). Competitive landscape and positioning: [`docs/competitive-analysis.md`](docs/competitive-analysis.md), [`docs/portablemind-positioning.md`](docs/portablemind-positioning.md).

---

## Why this exists

Markdown has become the lingua franca of LLM agentic knowledge work — especially in human-in-the-loop (HITL) processes. Agents read markdown, write markdown, hand it back to humans for review, and pick up where the human left off. Specs, plans, memories, handoffs, status reports, task lists — all markdown.

That loop currently privileges technical users. If you live in a code editor and a terminal, you're a full participant. If you don't, you're watching the loop happen from outside it.

**md-editor's purpose is to bring non-technical and semi-technical users into that loop as first-class participants, without dumbing it down for technical users.** It's a companion to our broader toolkit — not a replacement for VS Code or Obsidian, but a purpose-built surface for the markdown that flows between humans and agents.

### Audience, in priority order

1. **Non-technical users** — subject-matter experts, operators, reviewers, stakeholders. They need to open a file an agent produced, understand it, edit it, and hand it back without fighting the tool.
2. **Semi-technical users** — PMs, designers, analysts who edit markdown daily but aren't living in a terminal.
3. **Technical users** — engineers who already have editors they love. md-editor shouldn't insult them.

---

## Three principles

### 1. A companion for the agentic markdown loop

Two levels of "agent-aware":

- **Level 1 — Baseline.** A genuinely good markdown editor for people whose daily tool is Word or Google Docs, pointed at folders where agent-produced markdown actually lives. Persistent formatting toolbar, folder-tree navigation, clean typography, file-on-disk fidelity.
- **Level 2 — Active.** Bidirectional change detection plus an explicit **Submit** handoff signal. Agent writes → I see immediately; competing edits produce a diff, not a silent overwrite. I write → I click Submit ("your turn") rather than relying on the ambiguous "saved to disk."

Level 1 is table stakes for v1. Level 2 is the durable differentiator — no desktop markdown editor ships diff views, change attribution, or an explicit handoff signal today.

### 2. Native per-OS, shared non-code SDLC artifacts

We will eventually support macOS, Windows, and Linux — each as a **genuinely native experience**, not a lowest-common-denominator cross-platform shell.

- **Shared across OSes (single source of truth):** all non-code artifacts — product vision, user research, feature specs, data model, interaction design, acceptance criteria, test plans, documentation.
- **Per-OS (translated):** the implementation stack. Each platform gets the idiomatic toolkit and UX conventions of its host OS.

macOS comes first. This repo is the macOS implementation.

### 3. Markdown today, structured formats tomorrow

Markdown is today's format because it's where the agentic loop currently lives. The same HITL pattern is already emerging for JSON, YAML, workflow graphs, schema files, eval traces. We don't build any of that now, but we architect around **"document type" as a concept** — not hardcode markdown everywhere — so the core can grow.

---

## Technology stack

| Layer | Choice |
|---|---|
| Language | Swift |
| UI framework | SwiftUI primary, AppKit via `NSViewRepresentable` where needed |
| Text-editing engine | TextKit 1 with `NSTextView` (`NSTextTable` for GFM tables) |
| Markdown parser | swift-markdown (Apple), cmark-gfm for GFM-specific nodes |
| File watching | NSFilePresenter for open docs, DispatchSourceFileSystemObject for folders |
| Packaging (v1) | Direct-download DMG, Developer ID + notarization |
| Updates | Sparkle (EdDSA-signed appcast) |
| Local state | UserDefaults or small JSON; **no Core Data / SwiftData** |

Rationale and alternatives considered: [`docs/stack-alternatives.md`](docs/stack-alternatives.md).

---

## Building and running

Prerequisites: Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
source scripts/env.sh                              # sets DEVELOPER_DIR
xcodegen generate                                  # (re)generate MdEditor.xcodeproj
xcodebuild -project MdEditor.xcodeproj \
           -scheme MdEditor \
           -configuration Debug \
           -derivedDataPath ./.build-xcode \
           build
open ./.build-xcode/Build/Products/Debug/MdEditor.app
```

Run the UITest smoke check:

```bash
xcodebuild -project MdEditor.xcodeproj \
           -scheme MdEditor \
           -destination 'platform=macOS' \
           -derivedDataPath ./.build-xcode \
           test
```

### CLI wrapper

`scripts/md-editor` is a shell wrapper that routes through the app's `md-editor://` URL scheme.

```bash
./scripts/md-editor                         # launch / activate the app
./scripts/md-editor path/to/file.md         # open a file in a tab
./scripts/md-editor path/to/folder/         # set workspace root to a folder
```

---

## How this project is built

md-editor is built via the **PortableMind SDLC framework** at [`~/src/ops/sdlc/`](https://github.com/rickkoloski/pm-sdlc), using the **Native lifecycle**. Every non-trivial feature starts as a **triad** — a spec, a plan, and a CC (Claude Code) prompt — before any code is written.

- `docs/current_work/specs/` — what to build
- `docs/current_work/planning/` — how to build it
- `docs/current_work/prompts/` — CC instructions
- `docs/current_work/stepwise_results/` — completion records

Cross-deliverable guardrails live in [`docs/engineering-standards_ref.md`](docs/engineering-standards_ref.md). The informal deliverable ordering is in [`docs/roadmap_ref.md`](docs/roadmap_ref.md).

---

## Status

Grouped by area. Full per-deliverable ordering, change log, and supersession history live in [`docs/roadmap_ref.md`](docs/roadmap_ref.md).

| Area | State |
|---|---|
| **Foundation** — project scaffolding, source-mutation primitives, formatting toolbar | ✅ shipped (D1, D2, D4, D5) |
| **Workspace** — folder-tree sidebar, tabs, multi-file external-edit watcher, `CommandSurface` + URL scheme + CLI shim, scroll-to-line, toggleable line numbers, tab path affordances, tab tooltip + Reveal in File Tree | ✅ shipped (D6, D9–D11, D21, D22, D25) |
| **GFM table rendering** — native `NSTextTable` under TextKit 1; responsive column layout (CSS-Tables §3.9 slack-proportional + narrow-column threshold lock-in) | ✅ shipped (D16, D17, D24, D24.2). Earlier TextKit 2 deliverables (D8, D8.1, D12, D13, D15, D15.1) retired by D17 |
| **Persistence & connectors** — local `Save` / `Save As`, `Connector` abstraction, PortableMind directory tree + save-back, full PM file management (Save As / New File / Rename / Move / Delete / New Folder) | ✅ shipped (D14, D18, D19, D23, D23.1) |
| **Submit / Handoff** — Level 2 agent-aware verb; standalone-mode v1 with toolbar Submit button, per-session sidecar dir, save-then-submit semantics, heartbeat-based staleness pruning. First deliverable in the D3x agent-loop series. | ✅ shipped (D30) |
| **Connection-management UX** — Finder-style sign-in workflow; replaces the dev-only Debug-menu token affordance | ⏳ queued (D20) |
| **File-operations follow-ups** — directory rename/move, multi-select, drag-drop, cross-connector ops, Local-side delete/create-folder UI | ⏳ reserved (D26–D29) |
| **Packaging** — Sparkle, DMG, Developer ID, notarization | ⏸ deferred (D3 — gates on Apple Developer Program renewal) |

---

## License

Not yet licensed. Source is published for transparency during development. A license will be selected before v1.
