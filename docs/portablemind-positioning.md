# md-editor — Positioning vis-à-vis PortableMind

**Companion to:** `vision.md`, `competitive-analysis.md`
**Date:** 2026-04-22

---

## The observation that prompted this doc

During the Obsidian audition, the first impression was: *"this is an entire ecosystem."* That's accurate — Obsidian ships its own notion of vault, plugin registry, sync add-on, publish add-on, file-level encryption, community, etc. To get value, you adopt the ecosystem wholesale.

**That's exactly the failure mode md-editor should avoid**, because we already have an ecosystem: PortableMind (née Harmoniq). The useful framing is not "how do we build Obsidian-but-better." It's **"how does md-editor inherit what PortableMind already does, and contribute what PortableMind doesn't."**

---

## What PortableMind already provides

From the product pages, the about content, and the memory we've built up over the Harmoniq → PortableMind evolution:

| PortableMind capability | What it gives md-editor for free |
|---|---|
| **Knowledge Server** — persistent shared memory across sessions, teams, agents | md-editor doesn't need to invent "remember this across sessions." Agents and humans share context via the platform. |
| **Role/actor framing** — humans and agents occupy the same roles; no separate "agent console" | "Who edited this file?" maps to an existing actor model. Attribution isn't a new data structure; it's a platform primitive. |
| **Status machine (`StatusApplication`)** — transitions on tasks, projects, artifacts | "Submit" (the Level 2 handoff verb from the vision) doesn't need to be invented. It's a status transition on whatever work item the document belongs to. |
| **MCP bridge** — agents read/write platform state through MCP tools | An agent that wrote a markdown file into a folder can update status, leave notes, or pick up a handoff — all via existing tools. |
| **Files & Knowledge module** — vectorized, contextual document repository with AI search | Long-term, the folder md-editor points at *is* a Files & Knowledge scope. We don't build a separate indexer, search, or vector store. |
| **Multi-tenant identity and security** | Sharing a folder with a collaborator is tenant-scoped, not a separate sharing model. |
| **Projects / Tasks / Conversations** — the work context a document lives in | A doc isn't just a `.md`; it's a doc attached to a task, a conversation, a project. md-editor can surface that context without reinventing it. |

The one-line summary: **PortableMind is the ecosystem; md-editor is a native surface on it.**

---

## What md-editor contributes

PortableMind today is a web application. It is excellent as a shared board and a connective substrate. It is not, and should not try to be, the native desktop experience for a non-technical user editing a markdown document at their kitchen table at 9pm.

md-editor fills four gaps that the web platform can't (or shouldn't):

1. **Native per-OS feel** (Principle 2 from vision). Window chrome, menus, file dialogs, typography, keyboard idioms — all platform-idiomatic. Web can't match this without a lot of compromise.
2. **Word/Docs-familiar authoring UX** (Principle 1 audience). Persistent formatting toolbar, keyboard-shortcut contract, live-render editor. This is a desktop-app-shaped problem; browsers are where we'd land if we had to compromise, not where we should start.
3. **Local-folder fluency**. Agents write to folders. Users need to navigate, trust, and edit those folders the same way they navigate Finder. The desktop is the natural home for this; a web surface always adds indirection.
4. **Offline and low-ceremony access**. "Open this file an agent just wrote me" should work with zero login, zero vault setup, zero tenant context. Standalone mode is a feature, not a limitation.

---

## Integration posture: standalone-capable, PortableMind-aware

md-editor should run in two modes, same app:

### Standalone mode (default on first launch)
- Open any local folder or file.
- No account, no sign-in, no vault ceremony.
- All features of Level 1 agent-aware work (good markdown UX, toolbar, folder nav, external-edit detection).
- **Submit** writes a local marker — a sidecar file, a git commit, or a trailing `<!-- submitted: <time> -->` comment. Sufficient for a solo user working with Claude Code against a local repo.

### Connected mode (sign into a PortableMind tenant)
- Same editor, same folder navigation, same authoring UX.
- **Submit** becomes a real status transition via the PortableMind API / MCP. The gantt the team watches updates without translation or mirror — exactly the design the platform was built for.
- Documents in the open folder can be associated with Files & Knowledge artifacts (linked, not copied). Vector search, AI summaries, and cross-module context become available.
- The document's work context (task, project, conversation) can surface in a side panel if wanted. The user who doesn't want it never sees it.
- Attribution of edits is real (human vs. agent, identified actor) rather than inferred.

The cost of this posture is genuine but small: md-editor needs a clean abstraction layer between "the thing I'm editing" and "the platform facts about that thing." Standalone mode is the degenerate case where those facts don't exist.

---

## Mapping Level 2 agent-aware onto PortableMind primitives

From `vision.md`, Level 2 agent-aware is the durable differentiator: bidirectional change detection + explicit **Submit**. In a PortableMind-connected world, each piece has a natural home:

| Level 2 feature | Standalone realization | PortableMind realization |
|---|---|---|
| Agent writes → I see immediately | File watcher + reconcile-open-buffer | Same, plus Knowledge Server pushes a "file changed" event so the buffer updates even if the write happened via API rather than disk |
| I write → Submit | Git commit / sidecar marker | `StatusApplication` transition on the associated task or artifact; visible on the platform gantt |
| Diff view between my changes and an agent's | Git-style diff (no metadata beyond timestamps) | Diff annotated with actor (human name vs. agent name), plus the conversation or task that prompted the edit |
| Change attribution | File mtime + local user (weak) | Real actor identity from the platform |
| Staged handoff (human ↔ agent) | Manual — user tells agent "I'm done" in chat | Status transition is the handoff signal; agent watching the status transitions picks up automatically |

The architectural implication: **md-editor's Level 2 features are designed standalone-sufficient but PortableMind-superior.** A standalone user gets a plausible version; a connected user gets the real thing without the editor doing any extra work.

---

## What this rules out

Framing md-editor as a surface on PortableMind means deliberately *not* building certain things, even if competitors have them:

- **No proprietary sync.** Use the OS's file-system primitives for local; PortableMind for connected. Don't reinvent Obsidian Sync, Bear's cloud, or Ulysses' library-sync.
- **No search engine of our own.** Local mode uses whatever the OS provides (Spotlight on mac, Windows Search, etc.). Connected mode uses the Knowledge Server.
- **No AI chat sidebar.** The chat already exists in PortableMind and in the user's coding agent. md-editor's job is authoring, not conversation.
- **No identity or tenancy model.** Standalone mode has no user model; connected mode uses PortableMind's. No third option.

Each of these is a deliberate "we are not going to out-compete Obsidian on Obsidian's terms" decision — we're playing a different game.

### Deferred, not excluded: plugins and extensibility

The earlier draft of this doc listed a plugin marketplace as a non-goal. On reflection, that was too strong. Priority-3 users (technical) will reasonably want to extend md-editor, and the **document-type architecture from Principle 3 is itself an extension point** — every new document type is a plugin by another name. So extensibility is in scope, just not near-term:

- **Near-term (v1):** no public plugin API. The document-type registry is internal and markdown-only at first.
- **Medium-term:** when we add the second document type (JSON, YAML, or a workflow format), the registry becomes the surface a third party could target.
- **Long-term:** a plugin API follows naturally from the registry, but *not* an Obsidian-style free-form extension model — anything that extends the editor registers as a document type, a toolbar action, or a view. That discipline is what keeps md-editor from becoming an ecosystem of its own.

The difference from "no plugin marketplace" is positioning: we're not building a community plugin store as a differentiator, but we're not shutting the door on technical users extending the tool either.

---

## Open questions for later specs

1. **How is a document associated with a PortableMind entity (task, artifact, conversation)?** Options: front-matter key, a sidecar `.pm.json`, naming convention, or a PortableMind-side registry pointed at file paths. Front-matter is the most portable but bleeds into the document text.
2. **What does "sign into PortableMind" look like inside a native desktop app?** OAuth device flow? API token paste? macOS Keychain integration? This is a real UX question that affects first-run experience.
3. **How does a standalone-mode Submit upgrade to a connected-mode Submit?** If the user later signs in, should we retroactively link old Submits to tenant history, or is that line in the sand?
4. **Where does the "document type" concept (markdown today, JSON/YAML tomorrow) live — in md-editor, or in PortableMind?** Probably in md-editor as a client-side registry; PortableMind stays format-agnostic. But worth making the call explicitly.
5. **Cross-platform parity and PortableMind connectivity.** Windows and Linux versions presumably connect to the same tenant. The shared SDLC artifacts include the API contract; the per-OS clients implement it.

---

## One-sentence positioning

> **md-editor is PortableMind's native markdown surface on the desktop — a Word/Docs-familiar editor that lets non-technical users participate in human-in-the-loop agentic workflows without adopting a separate ecosystem.**

The Obsidian audit confirms the inverse: without a framing like this, a markdown editor is just another ecosystem competing for the user's attention and discipline. With PortableMind as the substrate, md-editor doesn't have to be an ecosystem — it can be the *view*.
