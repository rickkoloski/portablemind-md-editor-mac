# md-editor Vision — Ideation Companion

**Type:** Ideation. Companion to `vision.md`. Speculative, not committed. Captures threads worth keeping live but explicitly not part of the v1 product surface.

`vision.md` describes what md-editor *is* — a native markdown editor that brings non-technical and semi-technical users into the agentic HITL loop, native per-OS, designed to extend to other structured formats. This doc captures **what it could become** if specific threads pan out.

The bar for landing in here: an idea has to be (a) substantive enough to keep alive, and (b) far enough from v1 that putting it in `vision.md` would warp the product's center of gravity. Ideas graduate to `vision.md` only when we're committing.

---

## Thread 1: SDLC process automation companion for Claude Code

**Origin (2026-04-27, during the over-the-shoulder demo of the agentic editing loop):** the combination of the native editor + the SDLC framework artifacts in `~/src/ops/sdlc/` + Claude Code as a runtime suggested a larger product space — *"a slightly more recipe-based flow for less experienced users or for teams that we'd want to hew to a specific process or set of processes."* (Phrasing CD's, kept verbatim because it survived the test of articulation.)

The shape: a **process layer** that sits *above* Claude Code rather than around it. Different from IDE-class wrappers (Cursor, Continue) which are editor surfaces. CC stays the runtime; the companion provides:

- **Process recipes** — bug fix, tech spike, Scrum-like sprint, deliverable triad authoring, design review, etc.
- **Visual representation** of the active process (DAG of steps, current state, who's holding what).
- **Artifact + checkpoint shaping** — the recipe knows what artifacts a step produces, which checkpoints gate progress, what prompts CC should be running with.
- **Auditability for non-engineer stakeholders** — a team lead can look at the DAG and know exactly where a deliverable sits without reading the code.

### Why the seeds are already on disk

| Layer | What it is | Where |
| --- | --- | --- |
| Process content | Lifecycles (Native, Scrum, RUP, SAFe, Prototyping, Waterfall, Kanban), 10 disciplines, operations docs | `~/src/ops/sdlc/` |
| Process scaffolding skills | `project-setup`, `scaffold-project`, `{lifecycle}-descriptions.md` | `~/src/ops/sdlc/portablemind-skills/` |
| Artifact surface | Markdown editor with greppable markers (`**Question:**` → `**Decision:**`) + Decision log convention | md-editor-mac |
| Process visualization | DAG editor with Action / Decision / Join / Subprocess / Terminal / Wait nodes | `~/src/shared/wf` |
| Runtime | Claude Code | (already exists) |
| Work tracking | Harmoniq Projects app | PortableMind |


The workflow widget's node taxonomy maps almost 1:1 to SDLC process steps:

- **Action** → "draft spec," "run tests," "land commit"
- **Decision** → CD approval gate, build-or-buy fork
- **Join** → wait for parallel reviewers
- **Subprocess** → invoke a spike, invoke a focused testing pass
- **Terminal** → kickoff / done
- **Wait** → human review, soak window, exec review

CD drew the workflow editor for one domain and accidentally drew the universal SDLC process vocabulary.

### The wedge (if it pans out)

**Visual process as recipe; Claude Code as runtime.** The recipe layer is *auditable* by non-engineer stakeholders — a real organizational value that "the agent did the thing" alone can't deliver.

The right tension between rigidity and openness mirrors how the existing SDLC framework already treats lifecycles: **recommend a path, allow deviation, document the deviation.** Recipes guide; they don't railroad.

### Operating principle: manage by outcome, not by task

CD's articulation (2026-04-27, kept verbatim because the framing is the load-bearing piece):

> *"We've had quite good success by being very explicit with templates and examples, but refraining from trying to take away CC's creativity in terms of how to solve a problem. Similar to the old management-science axiom: 'manage by outcome, not by task'."*

**This isn't a CC-specific insight; it's a leadership maturity transition humans have been making for decades, now applied to a new substrate.** From CD's experience training teams in this style of work:

- **Senior architects approach CC fundamentally differently from programmers.** Architects already specify the outcome and let the implementer figure out the method — that's the job they've been doing with human teams for years. CC drops into that mental model unchanged.
- **Programmers strain to constrain CC the way they would solve the problem.** They don't think to specify the outcome and many actively resist the notion. The same posture that makes someone an effective individual contributor (deep "I know exactly how to do this" reflex) is the posture that fights outcome-management.
- **New human team leaders go through the same transition.** Replacing task-level micromanagement with deliverable / outcome management is the canonical growth challenge for first-time managers, especially leaders working with outsourced teams where presence-based supervision isn't an option. The CC equivalent is identical: you cannot watch CC do every keystroke; managing the tool by trying to is misery for both sides.

So the recipe layer is honoring an organizational practice that's already battle-tested with human teams — adapted for a new kind of worker. That's a much stronger framing than "AI process automation" because the value is grounded in something humans already understand and trust. It also predicts who will adopt the recipe layer fluently and who will fight it.

The existing SDLC framework already operates this way (and that's *why* it works):
- **Templates** dictate artifact shape (`spec_template.md`, `planning_template.md`, `stepwise_result_template.md`).
- **Completion assertions** define what "done" looks like at a deliverable level.
- **Discipline guidelines** describe quality bars in outcome terms ("every spec traces to a foundation doc," "every deliverable has a manual test plan").
- **Lifecycles** describe phase outcomes, not step-by-step playbooks.

What the framework explicitly doesn't do: "first, run command X; then edit file Y; then commit." That kind of task-scripting would reduce CC to a macro player and kill the value-add. The recipe-companion product, if it ships, has to inherit this discipline — recipes are outcome scaffolds, not task scripts.

This principle also resolves Hard Part #1 below before it becomes a hard part: there's no tension between "rigidity" and "openness" if the rigidity is on outcomes and the openness is on method. The two aren't competing dimensions; they're the X and Y axes of the design space.

### Hard parts

1. **Outcome-shape discipline at scale.** The operating principle above is easy to articulate and hard to enforce when recipe content is being authored by many hands. Recipes need a review pass that asks "is this telling CC *what good is* or *how to do it?*" — same discipline applied to specs in the SDLC framework already, but at a higher cadence.
2. **Recipe granularity.** "Run a Scrum sprint" is too coarse; "type this character" is too fine. The right unit is probably **deliverable** (D-numbered). Each deliverable instantiates a recipe; the recipe is a DAG.
3. **Process content is living.** `~/src/ops/sdlc/` evolves; recipes need to pin to versions. Versioning + deprecation is real work.
4. **Distribution model.** MCP server CC consumes? Companion app that wraps CC? Library CC imports? Each has different friction profiles.
5. **Multi-user.** Solo CC + recipe is one thing. A team where different humans drive different recipe steps is another (parallel-agent demos hint at this — the PM QA Lead session driving the same docs as the implementer session).

### Pondering questions worth keeping in the back pocket

- **Who is the first user?** Filter on **who's already crossed the outcome-management threshold**, regardless of role label. Senior architects, experienced engineering managers, leaders with outsourced-team experience — anyone who's already learned to manage what people produce rather than what people do — adopts the recipe layer fluently. Individual-contributor programmers who haven't crossed the threshold will fight it (they'll try to use recipes as task scripts, get frustrated when CC interprets them loosely, and conclude the tool is broken). The recipe layer's audience is filtered by where someone is in that transition — not by seniority, not by role. Open question: does the recipe layer need a teaching scaffold to help people across, or does it accept them as they are and let market self-selection do the filtering?
- **Is the visual representation primary or secondary?** If primary, the flowchart widget is the home. If secondary, the markdown is the home (CLAUDE.md + SDLC framework already work this way) and the DAG is a renderer over the same data.
- **What's the smallest demo?** Probably "click 'Bug fix' in a palette → CC runs through the bug-fix recipe → artifacts land in `docs/current_work/issues/` → Decision-log entries accumulate." If that demo is real, the rest is filling in.
- **Where does the editor itself fit?** The recipes produce markdown artifacts; md-editor is where humans review / amend them. The editor is naturally inside this loop — but it's not the recipe runtime, and conflating the two would warp both.

### Why this lives here rather than in `vision.md`

Two reasons:
1. **Different center of gravity.** `vision.md`'s center is the editor as a HITL surface for individual users. The recipe-companion idea makes the editor *one component of a larger system*. Putting that in vision.md would re-center the product around something we haven't committed to building.
2. **Speculative composition.** The recipe-companion idea depends on at least three other systems (SDLC framework, workflow widget, multi-agent CC orchestration) maturing in compatible ways. Each of those is its own bet.

If md-editor v1 ships and these threads stay live, this thread becomes a candidate for its own deliverable scoped against the editor — likely starting with **the editor as a participant in someone else's process recipe** (level 2 agent-aware in `vision.md` is already a step in that direction) before contemplating whether md-editor is also the home of the recipe library.

---

## Thread 3: Organizational diagnosis — the bottleneck is positioning, not intelligence

**Origin (2026-04-27, follow-on to Thread 1's operating principle):** while Thread 1 explains *how* the recipe layer should be designed, this thread explains *why so many organizations need one.*

CD's framing, quoted at length because the diagnosis is the load-bearing part:

> *"I think it's a substantial contributor to why some organizations struggle to get the promised value from agentic AI. They think 'the models just need to be smarter' — and I think that's completely the wrong framing. I've viewed any of the versions of Claude over the past year as more than capable of adding value if put in the right position and given the right framing, context and targets. That's really not much different of a thought exercise than if you gave me five SMEs I never met and I had to make a team out of them and figure out where the strengths and gaps were, where I should allow for more or less autonomy, where instructions would benefit from being broader or narrower."*

The claim, broken into testable pieces:

1. **The capability ceiling for value creation isn't at the model.** Claude has been capable of substantial value-add for at least the past year. Organizations that aren't getting that value are bottlenecked on **positioning, framing, context-shaping, and target-setting** — i.e., management — not on model quality.
2. **The skill required is general management of unfamiliar workers.** Not prompt engineering. Not fine-tuning. The cognitive activity of "given five strangers with unknown strengths, build a productive team" — which experienced leaders do continuously — is approximately the same activity as "given Claude with unknown-to-me strengths in this domain, build a productive working relationship."
3. **The 'we need smarter models' framing actively misdirects investment.** Organizations chasing that framing optimize for things that don't unblock them (model upgrades, prompt-tweak cycles, ever-larger RAG plumbing) while leaving the actual bottleneck (leaders who can't yet manage by outcome) untouched.

This diagnosis is *why* Thread 1's recipe layer is valuable, and why its audience filter (the leadership-transition threshold) is so sharp. It also opens up adjacent product / training / advisory possibilities beyond a recipe-companion app.

### Time horizon: until embodiment closes the experiential gap

CD's forward-looking claim, also kept verbatim:

> *"Not to be science fiction-y, but it will likely remain true to varying extents until AI is embodied to the point where you can be put in situations to have the experiential background that shapes a founder's intuition and context awareness."*

This is a sophisticated take on what current LLMs actually lack — not raw intelligence, but the experiential ground truth that comes from being in situations and accumulating embodied context. Current LLMs have *read about* being in situations; they haven't *been* in them. That gap is what management-by-outcome papers over: the human supplies the contextual ground truth (what "good" looks like, in this situation, for this team), and the model brings synthesis + execution against that frame.

Embodied AI narrows the gap as it accumulates situational experience. Until then, the human management layer stays load-bearing — and the leaders who already know how to do this kind of management are the ones who get value first.

### What stays load-bearing: the team-context layer

The diagnosis above is mostly about the *work-shaping* layer — outcomes, framing, targets. There's a deeper layer of management that's even harder for software to substitute for, and it stays load-bearing regardless of how well the recipe scaffold is designed: **the team-context layer.**

CD's compressed example, capturing the kind of observation that determines whether work actually happens:

> *"Jim is threatened. Jane wants to learn what she needs to earn a promotion."*

These look like soft adjacent details. They aren't. Two specific observations like this can 100% cause a project or team to fail if not considered. An experienced leader reads the room and makes hundreds of small adjustments accordingly:

- Don't assign Jim work that exposes his fear; pair him with someone who can teach him forward.
- Give Jane work that stretches her in the direction her promotion case needs.
- Frame the same outcome differently for each — different motivations, different language, same destination.

The recipe layer can capture **process knowledge** (what artifacts, what checkpoints, what completion criteria). It cannot capture **team-context knowledge** — who's threatened, who's hungry, who needs forward motion, who needs cover. That stays the human leader's job until AI is embedded in the social fabric long enough to perceive these dynamics directly. Reading about Jim being threatened isn't the same as catching the look on his face in standup.

This is the deepest reason the recipe layer pairs naturally with training and coaching (per Implications below): the most successful adopters won't just *use* the recipe layer — they'll be the kind of leaders who already practice team-context-aware management with humans and who pick up the recipe layer as a natural extension of that practice. The recipe layer gives them an outcome scaffold; their team-context fluency is what makes the outcomes actually land with real people.

### Implications

- **The recipe layer is more than a productivity tool.** It's organizational capability building, embedded in software. Each recipe is a captured management practice that less-experienced leaders can adopt without having to derive it themselves.
- **Training and tooling probably belong together.** If the bottleneck is management skill, software-alone misses the deeper work. The natural product shape pairs the recipe layer with coaching / examples / case studies — closer to "Khan Academy for managing AI workers" than "AI process automation tool."
- **Market positioning insight.** The buyers most likely to adopt successfully are the ones whose human-team management is already mature. Outsourced-team-experienced organizations, agency PMs, senior architects who've had to manage strangers' work for years — these are the early-adopter shapes. Organizations whose engineering culture is "we hire people who don't need management" will struggle.
- **Counter-narrative to the prevailing AI discourse.** Most enterprise AI conversations are framed around model capability, evaluation benchmarks, fine-tuning, and so on. This thread is the case for redirecting attention to the *human side* of the partnership — and there's a real audience hungry for that framing once it's articulated.

### Why this lives in vision-ideation rather than vision

`vision.md` is the editor's product vision. This thread is a much broader claim about how organizations should be working with agentic AI — relevant to the recipe-companion thread, but not specifically an md-editor product claim. If a separate "PortableMind capability building / training / advisory" surface ever emerges, this thread is its origin doc.

---

## Thread 2 (placeholder): Native flowchart editor as a sibling document type

If the SDLC-companion thread matures, the workflow editor in `~/src/shared/wf` becomes a strategic asset — but as **React + WKWebView host inside md-editor** vs **native rebuild** is a real fork. Surveyed 2026-04-27 (see conversation history); estimate ~6–10 focused weeks for a native rebuild anchored on AudioKit's [Flow](https://github.com/AudioKit/Flow) as a reference. The existing requirements + the domain model in `src/types/workflow.ts` survives either choice as the executable spec.

Tracked here so the analysis isn't lost. Not committed; revisit when the SDLC-companion thread shapes up enough to know whether the visual layer is primary or secondary.

---

## Conventions for this doc

- **Threads, not principles.** Each thread is a substantive idea worth keeping live. Threads can graduate to `vision.md` (commit), get archived (deliberately drop), or stay here (live but unscheduled).
- **Date the origin.** Each thread captures *when* and *why* it surfaced. Ideation context decays; the date helps future-us judge whether the assumption it rested on still holds.
- **Phrase verbatim where it lands well.** If CD or a discussion produced a sentence that survived articulation, keep it as a quote. Reframing later loses signal.
- **No commitments here.** This doc deliberately doesn't say "we will." If something becomes "we will," it migrates to `vision.md` or a deliverable spec.