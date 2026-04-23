# md-editor Vision

## Principle 1: A companion for the agentic markdown loop

Markdown has become the **lingua franca of LLM agentic knowledge work** — especially where we're modeling human-in-the-loop (HITL) processes. Agents read markdown, write markdown, hand markdown back to humans for review, and pick up where the human left off. Specs, plans, memories, handoffs, status reports, task lists — all markdown.

That loop currently privileges technical users. If you're comfortable with a code editor and a terminal, you're a full participant. If you're not, you're watching the loop happen from outside it.

**md-editor's purpose is to bring non-technical and semi-technical users into that loop as first-class participants, without dumbing it down for technical users.** It's a companion to our broader toolkit — not a replacement for VS Code or Obsidian, but a purpose-built surface for creating, reading, and editing the markdown files that flow between humans and agents in HITL processes.

### Audience, in priority order
1. **Non-technical users** — subject-matter experts, operators, reviewers, stakeholders. They need to open a file an agent produced, understand it, edit it, and hand it back without fighting the tool.
2. **Semi-technical users** — PMs, designers, analysts who edit markdown daily but aren't living in a terminal. They want speed and polish without ceremony.
3. **Technical users** — engineers who already have editors they love. md-editor shouldn't insult them; it should be pleasant enough to pick up when the context calls for it.

### Two levels of "agent-aware"

"Agent-aware" is doing real work in this vision, so it's worth defining precisely. There are two distinct levels, and we should be explicit about which one a given feature serves.

**Level 1 — Baseline agent-aware.** Non-technical users can fluently read and edit the markdown that agents produce, and produce markdown that agents can read. The agent context is the **motivation** for the product, not a feature in the product. At this level, "agent-aware" really means: a genuinely good markdown editor for users whose daily tool is Word or Google Docs, pointed at the folders where agent-produced markdown actually lives. Persistent formatting toolbar, folder-tree navigation, clean typography, file-on-disk fidelity — all serve Level 1.

**Level 2 — Active agent-aware.** Bidirectional change detection plus an explicit **Submit** signal for handoff.
- *Agent writes → I see immediately.* When an agent modifies a file I have open, the buffer updates without losing my place; if there are competing edits, I get a diff, not a silent overwrite.
- *I write → I click Submit.* "Saved to disk" is ambiguous — people save mid-sentence. **Submit** is an explicit verb that says "your turn." It can start minimal: a sidecar file, a git commit, or a trailing marker the agent watches for. Same mental model the user already has for submitting a PR or a review.

Level 2 is where there is no precedent in the competitive landscape (see `competitive-analysis.md` — no desktop markdown editor ships diff views, change attribution, or an explicit handoff signal). Level 1 has multiple partial answers (Obsidian + toolbar plugin, Bear if you ignore its DB-backed storage) but nothing that nails all of Level 1 and also runs natively per-OS.

### Other implications (to develop later)
- File-system fluency without requiring CLI fluency — if the agentic loop writes to a folder, the user should be able to navigate and trust that folder.
- Readability matters as much as editability — many HITL moments are "read carefully, then edit lightly."
- Level 1 is table stakes for v1. Level 2 is the durable differentiator and the reason we're building at all, rather than recommending Obsidian-plus-a-plugin.

---

## Principle 2: Native per-OS, shared non-code SDLC artifacts

We will eventually support macOS, Windows, and Linux. We want a **genuinely native experience** on each platform — not a lowest-common-denominator cross-platform shell (Electron, etc.).

To make that tractable without tripling our design/planning effort, we treat the SDLC layers asymmetrically:

- **Shared across OSes (single source of truth):** all non-code artifacts — product vision, user research, feature specs, data model, interaction design, acceptance criteria, test plans, documentation. These are written once and live above the stack.
- **Per-OS (translated):** the implementation stack. Each platform gets the idiomatic toolkit and UX conventions of its host OS. Claude helps translate the shared artifacts into the appropriate stack and platform idioms for each target.

### Why this matters
- A markdown editor lives or dies by feel — typography, keyboard behavior, window chrome, menu conventions, file dialogs. Cross-platform shells blur all of these.
- Writing the spec/design once (and keeping it honest about platform-neutral intent) lets us move faster on the second and third platform, not slower.

### Initial target
- macOS first (this repo name: `md-editor-mac`).
- Stack TBD — likely SwiftUI, but deferred until we've done enough planning to know what native features we actually need.

### Open questions (to resolve in later docs)
- How do we structure the repo(s) once we add Windows/Linux? One monorepo with `mac/`, `win/`, `linux/` siblings? Separate repos with a shared `docs/` submodule?
- Which artifacts are truly OS-neutral vs. which need per-OS variants (e.g., keyboard shortcut maps, menu structure)?
- What's our feature parity policy — lockstep, or is each platform allowed to lead/lag?

---

## Principle 3: Markdown today, structured formats tomorrow

Markdown is today's format because it's where the agentic loop currently lives. But the same HITL pattern — agents produce, humans review and edit, agents resume — is already emerging for **JSON, YAML, and other structured formats**: agent configs, tool definitions, workflow graphs, schema files, evaluation traces. If md-editor succeeds with markdown, the natural next move is to extend the same "friendly surface on technical content" philosophy to these formats.

We won't build any of that now. But we should make design choices today that don't foreclose it:

- **Architect around "document type" as a concept**, not hardcode markdown everywhere. A document has a type; the type determines the renderer, the toolbar, the validation, the affordances. Markdown is the first implementation of that pattern.
- **Keep the editor core format-agnostic where feasible.** Text buffer, file I/O, undo stack, cursor model, selection — these shouldn't care whether the content is markdown, JSON, or YAML.
- **Resist markdown-specific assumptions leaking into shared SDLC artifacts.** When we write specs for, say, the file browser or the agent-diff view, they should describe behavior in terms of "the open document" — not "the open markdown file."

### What "friendly surface on technical content" looks like for non-markdown formats (sketch, not commitment)
- **JSON/YAML:** form-like editing for known schemas (e.g., an agent config with named fields, validation inline), collapsible tree view for unknown schemas, never losing round-trip fidelity.
- **Workflow/graph formats:** visual node-and-edge view alongside the source, same read/edit/handoff loop.
- **Eval traces and logs:** readable summaries with drill-down to raw, annotations that agents can read back.

The through-line: whatever the file format, a non-technical user should be able to open it, understand it, edit it safely, and hand it back — without learning the underlying syntax.

---

## Reference products & lessons

As we survey the landscape, we're cataloging specific design decisions — good and bad — from existing markdown tools. These aren't features to copy wholesale; they're datapoints that clarify what our audience needs.

### Typora (https://typora.io/)
**Overall:** A well-regarded markdown editor with live rendering (no split preview pane — the markdown renders in place as you type). We like the feel and the restraint.

**Glaring weakness for our audience:** Formatting controls exist, but they're buried in a **dropdown menu** (Format menu / right-click). For users who live in MS Word and Google Docs every day, the absence of a visible **formatting toolbar** (bold, italic, headings, lists, links as always-on buttons) is a real adoption barrier. They will not go hunting through menus to bold a word — they will conclude the tool "doesn't do that" and leave.

**Implication for md-editor:** A persistent, Word/Docs-style formatting toolbar is not optional for our primary audience. It's the single most important affordance separating "tool a business user will adopt" from "tool a business user politely declines." The default must be: visible, labeled, familiar.

Power users who want a cleaner surface should hide it via the **View menu → Show/Hide Toolbar** convention that Word, Docs, Pages, and virtually every desktop app already use. This is the right escape hatch because it:
- Preserves the default-on experience for the primary audience.
- Uses a discovery path (View menu) that both casual and power users already know.
- Keeps the decision reversible and per-window/per-user rather than a config-file toggle.
