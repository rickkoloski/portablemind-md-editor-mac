# D11: CLI Control of Line Numbers (Explicit On/Off) — Specification

**Status:** Draft
**Created:** 2026-04-23
**Author:** Rick (CD) + Claude (CC)
**Depends On:** D6 (CommandSurface), D10 (line-numbers feature itself)
**Traces to:** `docs/engineering-standards_ref.md` §2.4 (CommandSurface declarative). Promoted from Harmoniq task #1380. Informed by the PortableMind **visible-entity-IDs** design principle — a visible line number is the text-level analogue of a task/file/message ID, sharpening agent↔human precision.

---

## 1. Problem Statement

D10 shipped the line-number gutter. The visibility is currently a user-manual toggle via View menu / `Cmd+Option+L`. For the agent↔human loop, **the agent needs to be able to declare the line-number state** before asking the user to look at a specific line — otherwise, "check line 42" requires the user to first turn on numbers.

The agent can't observe current UI state, so this must be **explicit on/off (idempotent), not toggle**. This is a cross-cutting discipline for all CommandSurface state setters.

---

## 2. Requirements

### Functional

- [ ] URL scheme: `md-editor://open?path=...&line_numbers=on|off` — combined with file open. Sets the line-numbers setting before showing the file.
- [ ] URL scheme: `md-editor://set-view?line_numbers=on|off` — standalone setter, no file operation. Useful for "turn numbers on for the next thing I hand you."
- [ ] CLI flag: `./scripts/md-editor --line-numbers=on|off [path[:line[:col]]]`. Composes with scroll-to-line suffix (#1367 / D9). Path optional when used standalone.
- [ ] Value parsing is strict: only `on` and `off` accepted. Any other value is a no-op with NSLog (consistent with D6 unknown-command handling).
- [ ] Setting writes through to `AppSettings.shared.lineNumbersVisible` — persists across relaunch via `@AppStorage` (same mechanism D10 established).
- [ ] `on on` is idempotent (no flicker, no side effect beyond the first apply).

### Non-functional

- [ ] Standards §2.4 — new command registered in `CommandSurface.registry`. Extension of `open` honors the same routing.
- [ ] **Never call `.toggle()` on CLI paths.** State setters assign declared values, not flips. This discipline is captured as a candidate §2.6 standard for future promotion (companion to §2.4).

### Out of scope

- Controlling other settings (toolbar, sidebar) via set-view. Architecture supports it; defer until use case surfaces.
- Multi-key atomic sets (`?line_numbers=on&toolbar=off`). The design permits this (see §3) but D11 only exposes `line_numbers`.
- Querying current state via CLI (the "read" half of idempotent state). Separate future deliverable; not needed for the agent-declarative path.

---

## 3. Design

### New `ExternalCommand`

`SetViewCommand` under `Sources/CommandSurface/`. Identifier `set-view`. Parses any number of `<key>=<value>` params and dispatches each to a small `ViewStateKey` mapping.

### Parameter table (D11 scope = one entry)

| URL-query key | AppSettings target | Accepted values |
|---|---|---|
| `line_numbers` | `lineNumbersVisible` | `on`, `off` |

Future keys slot in here (`toolbar`, `sidebar`, etc.) without a new command.

### `OpenFileCommand` extension

After opening / focusing the file, honor the same `line_numbers` param. Shared parsing helper to keep the two entry points consistent.

### Shell wrapper

Add `--line-numbers=on|off` flag. Flag is independent of the positional path and the `:line[:col]` suffix. Order among them doesn't matter.

Implementation: use bash `case` glob matching for flags first, then accept one positional path. Keep the implementation to ~30 added lines; no getopts.

### Discipline: assignment, not toggle

The implementation must never call `.toggle()` on the CLI path. The value comes from the caller; the command applies it as declared. Comment this in the `SetViewCommand.swift` source as a durable rule.

---

## 4. Success Criteria

- [ ] `./scripts/md-editor --line-numbers=on docs/roadmap_ref.md:30` — opens file, scrolls to line 30, line numbers visible.
- [ ] `./scripts/md-editor --line-numbers=off` (no path) — turns line numbers off globally.
- [ ] `./scripts/md-editor --line-numbers=on` twice — second invocation is a no-op at the settings layer (still `true`); no flicker.
- [ ] Bad value (`--line-numbers=maybe`) logs and no-ops (existing numbers state preserved).
- [ ] State persists across app relaunch (already covered by D10, confirmed unchanged).
- [ ] Grep: no `.toggle()` call introduced on the CLI path.

---

## 5. Implementation Steps

1. `ExternalCommand.swift` — add `setView = "set-view"` identifier.
2. `SetViewCommand.swift` (new) — iterate known view-state keys, parse on/off, assign to `AppSettings.shared.<key>`.
3. `CommandSurface.swift` — register `SetViewCommand`.
4. `OpenFileCommand.swift` — parse `line_numbers` param and delegate to the same helper.
5. `scripts/md-editor` — parse `--line-numbers=on|off` flag; append `&line_numbers=...` to the composed URL; when no path is given with a flag, emit a `set-view` URL instead of `open`.
6. Build, launch, dogfood.
7. COMPLETE doc, roadmap, commit.
8. Close Harmoniq task #1380 via `apply_status_tool`.
