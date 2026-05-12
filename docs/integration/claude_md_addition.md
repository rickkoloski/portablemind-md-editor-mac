# md-editor Submit / Handoff — agent convention

> **What this file is:** a self-contained snippet intended to be **copy-pasted into the CLAUDE.md of any project where a Claude Code session uses md-editor as a review/feedback surface.** It is asset-shaped on purpose — a future md-editor distro package may ship it as a startup hint or in-app help surface; until then, paste-into-CLAUDE.md is the install method.

---

## What Submit means in md-editor

md-editor is a native macOS markdown editor (`~/src/apps/md-editor-mac`). When a Claude Code session opens a markdown doc in md-editor with the `--session=<id>` flag (the shim defaults to `${MD_EDITOR_SESSION_ID:-$TERM_SESSION_ID}`), the editor registers the session's *interest* on that tab.

When the user clicks **Submit** on the toolbar (or presses `⌘⏎`), md-editor:

1. Saves the buffer first if it has unsaved edits.
2. Atomic-writes a JSON sidecar to `~/Library/Application Support/ai.portablemind.md-editor/submits/<session_id>/<unix-ms>-<short-doc-hash>.json` with this shape:

   ```json
   {
     "doc_path": "/abs/path/to/file.md",
     "doc_origin": "local",
     "doc_id": "<sha256-hex>",
     "session_id": "<your-session-id>",
     "submitted_at": "2026-05-11T15:22:33.421Z",
     "submitter": "Rick Koloski",
     "message": null
   }
   ```

This is the "your turn" signal. The user has reviewed, possibly edited, and handed the doc back to you.

---

## Your convention as the receiving agent

When a Submit event fires for a doc you authored:

1. **Re-read the doc first.** The on-disk content is authoritative. Submit implies save-then-emit; the user has saved their final state before signaling.
2. **Compare against what you wrote.** If the content has diverged substantially from what you authored, surface the divergence to the user before acting — they may have added a question, flipped a decision, or noted a conflict.
3. **Then proceed** with whatever the handoff was for: continuing the task, posting a status update, applying an edit, etc.

You can leave a `**Question:**` / `**Decision:**` / `**Assumption:**` / `**Bug:**` marker in the doc for the next round (project convention; see `memory/md_editor_dogfood_workflow.md` if you have access to that memory store).

---

## Operational setup for a Claude Code session

### 1. Set a stable session id (shell init)

```bash
# In ~/.zshrc, ~/.bashrc, or a tmux-pane-specific init:
export MD_EDITOR_SESSION_ID=cc1          # short slug; "cc1", "cc2", etc.
```

The id is opaque (≤64 chars). Short slugs are easier to read on the tab badge than UUIDs.

### 2. Start the heartbeat helper on session startup

```bash
~/src/apps/md-editor-mac/scripts/md-editor-heartbeat &
```

The heartbeat writes `heartbeat.json` into your session's sidecar dir every `MD_EDITOR_HEARTBEAT_INTERVAL_SEC` seconds (default 60). The editor's periodic prune sweep uses this to release stale interests from sessions that crashed without cleanup.

### 3. Stop the heartbeat on session exit

```bash
kill %1                                   # if backgrounded as job 1
```

Or wire it into a session-end trap if you have one.

### 4. Disable knobs (if needed)

- `MD_EDITOR_HEARTBEAT_INTERVAL_SEC=0` — the helper exits immediately without writing.
- Editor-side: set `UserDefaults.standard.set(0, forKey: "submitStalenessTimeoutSec")` — the prune sweep no-ops.

---

## Watching for Submit events

Each session has exactly one sidecar dir. Watch it with whatever filesystem-watch primitive your runtime exposes:

```bash
SUBMITS="$HOME/Library/Application Support/ai.portablemind.md-editor/submits/$MD_EDITOR_SESSION_ID"
fswatch -0 "$SUBMITS" | while read -d "" event; do
  # `event` is a path; if it ends in .json and isn't heartbeat.json, it's a Submit.
  ...
done
```

Or `inotifywait`, or your language's native API. The atomic-write guarantee (`Data.write(options: .atomic)` writes to a sibling tmp + rename) means a watcher reading the file when it appears will always see the complete payload — never a partial JSON.

---

## Opening a doc to ask for feedback

```bash
~/src/apps/md-editor-mac/scripts/md-editor /path/to/draft.md
```

The shim auto-injects `--session=$MD_EDITOR_SESSION_ID`. The editor opens the doc, registers your interest, and the user can edit + Submit when they're done.

To explicitly opt out of registering interest (e.g., opening a doc for the user without expecting a handoff):

```bash
~/src/apps/md-editor-mac/scripts/md-editor /path/to/draft.md --session=
```

To release your interest (e.g., you decided not to wait):

```bash
~/src/apps/md-editor-mac/scripts/md-editor --release /path/to/draft.md
# or release every interest you hold:
~/src/apps/md-editor-mac/scripts/md-editor --release --all
```

---

## Constants worth knowing

| Constant | Value |
|---|---|
| Sidecar root | `~/Library/Application Support/ai.portablemind.md-editor/submits/` |
| Per-session dir | `~/Library/Application Support/ai.portablemind.md-editor/submits/<session_id>/` |
| Heartbeat file | `<per-session-dir>/heartbeat.json` |
| Submit filename pattern | `<unix-ms>-<short-doc-hash>.json` |
| URL scheme | `md-editor://open?...&session=...` and `md-editor://release?session=...` |
| Default heartbeat cadence | 60s (`MD_EDITOR_HEARTBEAT_INTERVAL_SEC`) |
| Default staleness threshold | 300s (UserDefaults `submitStalenessTimeoutSec`) |

---

*Asset version: D30 v1 (2026-05-11). Future revisions: connected-mode Submit (PortableMind status transition), Submit-with-message UI, multi-session-per-doc UX.*
