# D11: CLI Control of Line Numbers — COMPLETE

**Shipped:** 2026-04-23
**Spec:** `docs/current_work/specs/d11_cli_line_numbers_spec.md`
**Promoted from:** Harmoniq task #1380

---

## What shipped

- `md-editor://set-view?line_numbers=on|off` — new standalone CommandSurface verb.
- `md-editor://open?…&line_numbers=on|off` — view-state ride-along on the existing open command.
- `./scripts/md-editor --line-numbers=on|off [path[:line[:col]]]` — shell flag, composes with D9 suffix notation and with standalone (no-path) invocations.
- Strict `on` / `off` / `true` / `false` / `1` / `0` parsing; anything else NSLogs and no-ops.

Dogfood sequence passed one-at-a-time: baseline off; on+scroll to line 30; off standalone; on + second on (idempotent, no flicker). Real-world demo of `md-editor --line-numbers=on vision.md:50` worked — exact-line agent→human handoff pattern validated.

## Files created / modified

| File | Action |
|---|---|
| `Sources/CommandSurface/SetViewCommand.swift` | Create — includes shared `ViewStateApplier` |
| `Sources/CommandSurface/ExternalCommand.swift` | Modify — add `setView` identifier |
| `Sources/CommandSurface/CommandSurface.swift` | Modify — register SetViewCommand |
| `Sources/CommandSurface/OpenFileCommand.swift` | Modify — delegate to ViewStateApplier for view-state params |
| `scripts/md-editor` | Modify — parse `--line-numbers=on\|off` flag |
| `docs/roadmap_ref.md` | Modify — D11 entry |

## Discipline captured

**CLI state setters assign declared values, never toggle.** Agents issuing commands cannot observe UI state; `on`/`off` are idempotent. Comment lives in `SetViewCommand.swift` doc block. Candidate engineering-standards §2.6 for future promotion when the next standards bundle lands.

## Known polish items

- CLI-triggered scroll-to-line lands correctly but the text view isn't first-responder afterward, so the caret isn't drawn. Noticed during D11 dogfood. Not a D11 blocker; backlog when the behavior bothers real usage.

## Related Harmoniq task

#1380 — to be closed via `apply_status_tool` after this commit.

## Dogfood evidence

CD ran `./scripts/md-editor --line-numbers=on vision.md:50` as the closing demo. Line numbers came on AND vision.md scrolled to line 50 in one invocation. This is the full realization of the PortableMind **visible-entity-IDs** design principle applied to the text surface — an agent can declare "look at line 50 with numbers visible" in one command, and the human sees exactly that.
