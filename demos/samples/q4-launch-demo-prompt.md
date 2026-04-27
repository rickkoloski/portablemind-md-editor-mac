# Demo: agentic editing loop in PortableMind Markdown

A short (~30–60s) demo of the dogfood loop: human prompts CC → CC reads, edits the open doc → editor reflects changes live via the external-edit watcher → CC flags a question inline → human jumps to the question.

## Setup (before recording)

**Reset first.** The demo mutates the doc; before each take, restore the canonical version so Prompt 1's status summary lines up:

```bash
cd ~/src/apps/md-editor-mac
git checkout demos/samples/q4-launch-roadmap.md   # once the file is tracked
```

If the file isn't yet tracked in git, leave the canonical copy on disk and don't commit the demo edits — only commit a return to canonical.

Then open the doc in the editor so the live-update is visible:

```bash
~/src/apps/md-editor-mac/scripts/md-editor \
  ~/src/apps/md-editor-mac/demos/samples/q4-launch-roadmap.md
```

Position the editor window where it's visible during the recording, alongside the Claude Code session.

## Prompt 1 — context check

> Can you check the Q4 launch roadmap and tell me where we are?

**Expected CC behavior**: read the doc, summarize. Something like:
- 2 done (brand, landing copy)
- 2 in progress (API inventory, onboarding wireframes)
- 3 pending: QA test plan (gated on API contract), launch announcement (gated on pricing), beta feedback synthesis (no gate)
- 1 blocked: pricing decision (awaiting exec review)

No file edits in this beat. Just status awareness.

## Prompt 2 — incremental status updates

> I wrapped up the API endpoint inventory and the onboarding flow wireframes yesterday. Update the status for both, and add yesterday's date to recent activity.

**Expected CC behavior**: edit `demos/samples/q4-launch-roadmap.md` with **deliberate small pauses between writes** so the editor's external-edit watcher reflects each change visibly. Suggested cadence: edit one row, sleep ~1.5s, edit the next row, sleep ~1.5s, append the activity entry.

Each edit triggers `NSFilePresenter` to refresh the buffer in the open editor window. Observers see the table cell flip from 🟡 to ✅ in real time.

For CC: drive this with explicit `Edit` + `Bash sleep` calls, e.g.:
1. `Edit` row "API endpoint inventory" → `✅ Done`
2. `Bash sleep 1.5`
3. `Edit` row "Onboarding flow wireframes" → `✅ Done`
4. `Bash sleep 1.5`
5. `Edit` "Recent activity" — prepend an entry for yesterday's date.

## Prompt 3 — question handoff

> Anything I should be looking at?

**Expected CC behavior**: notice that the API endpoint inventory just locked, which unblocks QA's test plan — but QA still needs a *contract artifact* to write against. There's a real technical fork here. Add a `**Question:**` marker just below the table framing it as an either/or with a recommendation (own line, content self-contained per the dogfood convention at `~/src/shared/prompts/use-md-editor.md`):

```markdown
**Question:** API endpoint inventory is locked, so QA can start the test plan — but they need a contract artifact to write against. Two paths: (a) generate an OpenAPI 3.1 spec from the inventory (~1d), QA authors tests against the spec, the spec doubles as customer-facing API docs at launch; (b) point QA at staging and let them probe live endpoints directly — faster start, but tests drift as endpoints change. Recommend (a) — we'd be paying for the launch docs anyway, so single source of truth.
```

Then in the Claude Code session, surface the question with a line pointer. CC should respond with something like:

> Updated. Both items moved to ✅ and added to recent activity.
>
> One thing for you: I dropped a `**Question:**` on line N — QA needs a contract artifact to start, and there's a fork between an OpenAPI spec (slower start, doubles as launch docs) and probing staging directly (faster, but tests will drift). I recommended the OpenAPI path; worth a look if you want to override.

CC can use `~/src/apps/md-editor-mac/scripts/md-editor demos/samples/q4-launch-roadmap.md:N` to focus the editor on the question's line if recording the editor following the focus.

## Reset between takes

```bash
cd ~/src/apps/md-editor-mac
git checkout demos/samples/q4-launch-roadmap.md
```

The doc is back to its canonical state. Restart the demo.

## What this demonstrates

- **Dogfooded markdown surface**: PortableMind Markdown is the visible artifact of the workflow; the human reviews work in a native editor while the agent does the writing.
- **Live external-edit reflection**: the file watcher (`NSFilePresenter`) reflects agent writes into the open buffer without explicit refresh — the editor doesn't need to know an agent is involved.
- **`**Question:**` convention**: a uniform, scannable, greppable marker for "needs human attention." Pairs with `~/src/shared/prompts/use-md-editor.md` (the prompt other agents adopt to participate in the loop).
- **Locality of attention**: the agent points the human at a specific line, not at "the doc"; the human sees exactly what to act on.
