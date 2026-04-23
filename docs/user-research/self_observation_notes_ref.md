# Self-Observation Notes — md-editor-mac as its own use case

**Type:** Reference (user-research log)
**Status:** Active — extended over time
**Started:** 2026-04-22
**Maintainer:** Rick (CD) + Claude (CC), with CC prompted to capture observations in real time when friction occurs

## Purpose

md-editor-mac exists to make non-technical and semi-technical users first-class participants in HITL agentic loops around markdown. The CD/CC pair working on this project **is itself that workflow** — we produce, review, and edit markdown docs in a human+AI loop as the main mode of collaboration. That makes every friction point we encounter with our current tools (VS Code source + preview, terminal, raw-markdown reading in chat) a genuine user-research datapoint.

This file is the growing log of those datapoints. It is **not a deliverable** and has no D-number. When a feature spec is written later (toolbar, navigation panel, diff view, Submit UX, folder tree, …), the author should mine this file for concrete motivating examples.

Observations are dated and grouped by the **product surface** they inform, so a future reader writing the "D-n formatting toolbar" spec can `grep` for "Toolbar" and find everything relevant.

### Capture rules
- **Real time beats retrospective.** When a friction moment happens and is noticed, write it down before the moment fades. Even two sentences is enough.
- **Specific over abstract.** "Couldn't find the competitor-matrix heading I'd just been looking at" is useful; "navigation is hard" is not.
- **Both pain and workaround.** Record what hurt *and* what we actually did instead — the workaround is itself a feature hint.
- **Honest about severity.** Minor (Workflow cost <1 minute), Moderate (1-5 min or noticeable interruption), Severe (derailed the work or forced a worse decision).

---

## Session: 2026-04-22 — Bootstrapping md-editor-mac

Context: a single working session that produced four foundation docs (vision, competitive analysis, PortableMind positioning, stack alternatives), bootstrapped the SDLC skeleton, and drafted D1. Rick read every doc. Most reading was in the chat rendering; some in VS Code with the built-in Markdown Preview. No dedicated markdown editor was used because none of the ones we evaluated fit — which is the whole point.

### Toolbar (persistent formatting toolbar — the Typora "buried format menu" principle)

- **2026-04-22 — Non-observation, which is itself an observation.** In seven hours of heavy markdown work, Rick never once reached for a format button — because he wasn't authoring prose, he was *directing* me to author prose. His role was "reviewer and editor," not "typist." This flips the toolbar-for-whom framing: for the *technical CD* in this loop, the toolbar matters less than it does for the non-technical reviewer downstream. Severity: **informational**. Implication for spec work: the toolbar is primarily for the non-technical audience reading/editing *our* output, not for us while we produce it. Personas matter.

### Tables (parsing markdown tables as a reader)

- **2026-04-22 — Competitive-analysis matrix rereading.** The main competitor matrix is 30 rows by 9 columns in raw markdown. Rick read the post-verification version to spot-check cells, and scanning the raw `| ... | ... | ... |` lines was slow. In a rendered view (e.g., VS Code Preview) it's tolerable; in the chat stream it's worse because the pipes dominate. Workaround: Rick trusted the agent's summary of changes rather than re-reading the raw cells. Severity: **moderate**. Spec implication: **tables are a first-class visual element**, not just formatted text — a live-render view should turn them into real visual tables (Bear and Mark Text both do this). Raw-pipe rendering is where even a technical user gives up.

- **2026-04-22 — Stack-alternatives option tables.** The `stack-alternatives.md` doc has five short option tables (4-6 rows each). These were read in the chat, not in a Markdown preview. Smaller tables parse fine in raw markdown. Severity: **minor**. Spec implication: table-rendering value scales with table size and column count; short reference tables are tolerable raw, 9-column matrices are not.

### Diff view / "what changed since I last read this"

- **2026-04-22 — Vision doc renumbering.** Rick approved adding Principle 2 (purpose), which I wrote as "Principle 2" above the existing "Principle 1" (native-per-OS). I flagged that the numbering was inverted. Rick said to renumber. I did it with a `Write` that rewrote the whole file. Rick had **no efficient way to verify the renumber was clean and nothing else changed.** He had to trust me, or scroll the chat's tool-call block. Severity: **moderate — trust is the workaround**. Spec implication: **a diff view for "show me what CC changed since the last time I read this" is a real product feature**, not a nice-to-have. It's the Level-2-agent-aware attribution primitive made visible.

- **2026-04-22 — Competitive analysis verification pass.** The verification subagent reported "~20 cells changed" and wrote a Verification Log at the bottom of the doc. Rick didn't read the log in detail — he relied on the agent's 150-word summary. That's a reasonable shortcut but it means **cell-level edits slip through unreviewed**. Severity: **moderate in ordinary work; severe in a regulated/high-stakes doc.** Spec implication: diff view should be scoped to "show me only the cells CC changed" not "re-render the whole doc"; the Verification Log pattern (human-readable changelog inside the doc) is a content primitive the editor can recognize and display specially.

- **2026-04-22 — "Two levels of agent-aware" insertion.** Rick described the Level 1 vs Level 2 distinction; I edited vision.md's "Implications" section into a new "Two levels of agent-aware" section with a list underneath. Rick approved by assertion ("looks good") rather than by reviewing the edit. Same class as the renumbering: **trust is the workaround.** Severity: **moderate**.

### Navigation (find a heading, re-read a section)

- **2026-04-22 — "Where was the toolbar section I was reading?"** After the Obsidian audition, Rick came back to the competitive analysis to find the Typora row and the toolbar dimension rows. In raw markdown that's Cmd+F or manual scrolling; in VS Code's Outline panel it would be one click. Severity: **minor but repeated** — a frequent small friction that accumulates. Spec implication: **a document outline / heading navigator** is not a power-user luxury. It's how a reader orients themselves in a 200-line document. Word and Docs both surface it by default; markdown editors often bury it.

- **2026-04-22 — Cross-document references.** Multiple times across the session we referenced `docs/stack-alternatives.md §Axis 2` or `docs/vision.md Principle 1`. In raw markdown / Finder world, that means open the file, scroll to the section. In a real editor: clickable cross-document links would be huge. Severity: **moderate, accumulates fast when working across a doc set.** Spec implication: **wiki-style / cross-doc linking is high-value** even when we're not building Obsidian. The PortableMind-positioning doc is full of references that would light up as hyperlinks.

### Folder tree / file browsing

- **2026-04-22 — Implicit mental model of `docs/`.** Rick and I both navigated `docs/` by naming files explicitly ("vision.md", "docs/current_work/specs/d01_*"). Working correctly required holding the directory layout in our heads. We've both done it for a long time so the cost is low, but it would be a wall for a non-technical user trying to join the project. Severity: **minor for us, severe for our audience.** Spec implication: the folder tree is non-negotiable for non-technical users; for technical users it's nice. Validates the competitive-analysis rating of folder-tree as a standard expectation.

### External-edit / agent-write detection (Level 2 agent-aware, baseline)

- **2026-04-22 — CC writes, Rick reads; repeat.** The entire session was a series of CC `Write` operations producing or updating docs in `apps/md-editor-mac/docs/`. Rick's editor (VS Code) did detect external changes correctly and reloaded — no friction observed on that axis. **Severity: none — confirms the baseline works when the editor implements it properly.** Spec implication: VS Code sets a real bar for external-edit detection that md-editor-mac must match. iA Writer was downgraded to "Partial" in our competitive analysis based on forum reports; validate against that bar during D1 or D2.

### Submit / handoff primitive (Level 2 agent-aware, active)

- **2026-04-22 — Implicit handoffs via chat turns.** Every "your turn / my turn" transition in the session happened as a chat turn, not as a file-system event. When Rick said "approved" or "Path A," those were **Submit events** in everything but name — "I'm done reviewing, agent please proceed." There's no on-disk record of them; they live in the chat history. Severity: **moderate — it works inside this one tool (Claude Code) but breaks the moment we split into editor-plus-agent.** Spec implication: when md-editor-mac exists, Submit should make these handoffs **visible artifacts** — in standalone mode as sidecar markers or git commits; in PortableMind-connected mode as status transitions on the related task. This is why `portablemind-positioning.md` describes Submit as "an explicit verb" rather than a surprise primitive.

- **2026-04-22 — Partial-edit approvals.** Several times Rick approved a direction with partial specificity ("that posture gives me enough to recommend" → full stack-alternatives draft; "yes please" → full positioning doc). The asymmetry between a one-line approval and a 400-line response is load-bearing for velocity. Severity: **informational.** Spec implication: Submit needs to be lightweight — one keystroke or one click — because the forcing function is speed, not ceremony.

### Visual density / readability of reference docs

- **2026-04-22 — Citations in line versus at the bottom.** The competitive-analysis verification pass added footnote-style inline citations, which made several paragraphs dense. Rick didn't read the footnotes during spot-checks — they added verification rigor but cost some fluency. Severity: **minor, but it's a real ergonomics tradeoff.** Spec implication: a live-render editor should **collapse dense syntax that the reader doesn't need right now** — footnote markers could render as small superscript hyperlinks, hideable. This is the same "source reveal on cursor entry" pattern as bold/italic, applied to a different element.

### First-run / onboarding (for the Obsidian audition)

- **2026-04-22 — "Settings → Community plugins → turn off Safe Mode → Browse → install".** Rick got the toolbar plugin running in Obsidian, but noted that the install path was five deliberate steps — and this was for a user who already understood what "Safe Mode" meant. For a non-technical user (priority-1 audience), that's a wall, not a ramp. Severity: **severe for audience fit.** Spec implication: if md-editor-mac ever has extensions/plugins (stack-alternatives says "deferred, not excluded"), the activation path must be **zero-ceremony** — nothing resembling the Obsidian Safe Mode dance.

### Meta observations (about the research itself)

- **2026-04-22 — The first competitive-analysis pass was synthesis dressed as research.** A well-structured doc is trusted, even when it's under-sourced; Rick had to actively push back with "we want to build a REAL product, so we might as well do REAL research" to prompt the verification pass. Severity: **moderate, on the research process itself.** Spec-adjacent implication: **provenance markers** (which cells have sources, which are inferred) are valuable content we should render distinctively in-editor — fits the "document-type registry" Principle-3 vision because it's a content-aware rendering decision, not a formatting one.

---

## Mining this file — how to use it in spec work

When writing a feature spec, `grep` for the feature's surface name or the implication keyword:

- Toolbar / formatting: search "Toolbar"
- Table rendering: "Tables"
- Diff view: "Diff view"
- Navigation: "Navigation"
- Folder tree: "Folder tree"
- External-edit detection: "External-edit"
- Submit: "Submit"
- Readability / live-render: "Visual density", "readability"
- Onboarding: "First-run"

Each observation is date-stamped so we know how stale it is. Re-observe as our tools change.
