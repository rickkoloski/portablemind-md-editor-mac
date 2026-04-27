# D18 Manual Test Plan — Workspace connector + PortableMind directory tree

**Spec:** `docs/current_work/specs/d18_pm_connector_directory_tree_spec.md`
**Plan:** `docs/current_work/planning/d18_pm_connector_directory_tree_plan.md`
**Date authored:** 2026-04-27

This plan is the human-runnable mirror of the harness-driven verification used through phases 1–5. Each section captures what to do, what to expect, and which harness action(s) prove the same behavior programmatically (per `docs/engineering-standards_ref.md` §0.1 / D18 plan §0.1 — harness-first).

---

## Setup

1. Build a Debug app:

   ```bash
   cd ~/src/apps/md-editor-mac
   source scripts/env.sh
   xcodebuild -project MdEditor.xcodeproj -scheme MdEditor \
     -configuration Debug -derivedDataPath ./.build-xcode build
   ```

2. Launch:

   ```bash
   open ./.build-xcode/Build/Products/Debug/MdEditor.app
   ```

3. Seed a PortableMind bearer token. Either:
   - **Debug menu:** *Debug → Set PortableMind Token…* → paste a JWT bearer (e.g. extracted from `claude mcp list | grep harmoniq`).
   - **Harness:** write `{"action":"pm_token_set","token":"<jwt>","path":"/tmp/mdeditor-pm-token-set.json"}` to `/tmp/mdeditor-command.json`.

4. *File → Open Folder…* to pick a workspace folder (any folder with `.md` files works; `~/src/apps/md-editor-mac/docs` is the canonical demo set).

---

## §A — Sidebar structure

**Goal:** Multi-root sidebar shows Local + PortableMind side-by-side.

| # | Action | Expected | Harness assertion |
|---|--------|----------|-------------------|
| A1 | Open the app fresh, with no folder + no token. | Sidebar shows the empty-state hint: "No folder open" + "Or set a PortableMind token in the Debug menu". | `dump_sidebar_state` → `{"roots": []}` |
| A2 | Open a folder via *File → Open Folder…*. | "Local" root row appears; root expanded by default; direct children render. | `dump_sidebar_state` → 1 root, `connectorID: "local"`, `expanded: true`, `loaded: true`. |
| A3 | Set a PM token (Debug menu OR harness). | "PortableMind" root row appears below Local; root expanded by default; spinner while loading; children render once `/llm_directories?parent_path=/` returns. | `dump_sidebar_state` → 2 roots; PM root `connectorID: "portablemind"`, `expanded: true`, `loaded: true`, child count > 0. |
| A4 | Clear token via *Debug → Clear PortableMind Token*. | PortableMind root disappears; Local stays. | `dump_sidebar_state` → 1 root (local). |

---

## §B — PortableMind tree expansion

**Goal:** Lazy-load on expand; cached after first load; error states render inline.

| # | Action | Expected | Harness assertion |
|---|--------|----------|-------------------|
| B1 | Click chevron next to a PM directory with `subdirectory_count > 0`. | Spinner briefly, then directory expands with its children loaded from `/llm_directories?parent_path=<path>`. | `expand_sidebar_path {connectorID: "portablemind", path: "/<dir>"}` then `dump_sidebar_state` shows expanded + loaded subtree. |
| B2 | Collapse the same directory; re-expand it. | Re-expansion is instant (no spinner). The view-model preserves the loaded subtree. | `collapse_sidebar_path` → `expand_sidebar_path` → no extra network call (verifiable via Charles Proxy or rails log). |
| B3 | Drill three levels deep. | Each level lazy-loads. No browser-tab-style "all-tree" preload. | `dump_sidebar_state` recursively reflects expanded subtrees. |
| B4 | Set an INVALID token; trigger reload. | PM root shows inline error: "Server 400: invalid tenant" (or similar). No crash. | `dump_sidebar_state` PM root has `error: "..."`, `loaded: false`. |
| B5 | Disconnect from network, click expand on an unloaded dir. | Inline error row: "Network: <message>" with retry chevron. | `dump_sidebar_state` shows the error on the affected node. |

---

## §C — Cross-tenant badges

**Goal:** Pill badge appears with correct initials, colors (#FCE4EC/#E5007E), and tooltip when `node.tenant.id != currentUser.tenant_id`.

| # | Action | Expected | Harness assertion |
|---|--------|----------|-------------------|
| C1 | Find a known cross-tenant folder (e.g. *NAHQ* — EpicDX-shared). | Pink pill with letter "E" appears to the right of the folder name. | `dump_sidebar_state` → node has `tenantBadge: {initials: "E", tooltip: "EpicDX", fgHex: "#E5007E", bgHex: "#FCE4EC"}`. |
| C2 | Hover over the badge for ~1 second. | Tooltip reads the full tenant name ("EpicDX"). | Tooltip is AppKit-managed; not directly introspectable from harness. |
| C3 | Find a multi-word cross-tenant entry (e.g. *Technical Docs* — Rock Cut Brewing Company). | Badge reads "RC". | `dump_sidebar_state` → `tenantBadge.initials == "RC"`. |
| C4 | Find a same-tenant folder (e.g. *App Data*, *Screenshots*, *Sales & Marketing*). | No badge. | `dump_sidebar_state` → `tenantBadge` is absent / null. |
| C5 | VoiceOver / accessibility inspector. | Badge announces "shared from <tenant.name>". | Verified via `accessibilityLabel` set in `TenantInitialsBadge`. |

---

## §D — Unsupported file rows

**Goal:** Non-`.md` files appear in the tree but are visually disabled and non-interactive.

| # | Action | Expected | Harness assertion |
|---|--------|----------|-------------------|
| D1 | Drill into a directory with mixed file types (e.g. *Images*, which has `.png` + `.jpg`). | Files appear in the list. `.png`/`.jpg` rows are greyed; their text uses `secondary` color. | `dump_sidebar_state` → `kind: "file", supported: false` for those rows. |
| D2 | Hover over a disabled row for ~1 second. | Tooltip: "file type not supported". | Verified via `.help()` modifier; tooltip captured by AppKit. |
| D3 | Click a disabled row. | No-op. No tab opens. | `connector_open_file` against the path → succeeds at the connector level, but UI tap is suppressed by the `node.isSupported` gate in `ConnectorRowView.handleTap`. |
| D4 | Click a `.md` file. | New tab opens (see §E). | — |

---

## §E — Read-only file open from PortableMind

**Goal:** Click a `.md` file in the PM tree → read-only tab. Save commands are greyed.

| # | Action | Expected | Harness assertion |
|---|--------|----------|-------------------|
| E1 | Click a `.md` file in the PM tree (e.g. */rockcut-site-guide.md*). | New tab opens; tab title = filename; small "READ-ONLY" pill next to the title. | `connector_open_file {connectorID: "portablemind", path: "/<file>"}` → `{ok: true, byteCount: N}`. `focused_doc_info` → `isReadOnly: true, origin.kind: "portablemind"`. |
| E2 | Type into the editor. | Nothing happens. (`isEditable = false` on the NSTextView.) | `set_text` against the read-only tab is a no-op; `dump_state` shows storage unchanged. |
| E3 | Try ⌘S. | Menu item is greyed; the chord doesn't fire. | `dump_command_state` → `save: false, saveAs: false, reason: "focused tab is read-only"`. |
| E4 | Try ⌘⇧S. | Same. | Same. |
| E5 | Click a different PM `.md` file. | New tab; the previous tab stays open. | TabStore de-dupes on (connectorID, fileID). |
| E6 | Click the same PM `.md` file again. | Existing tab refocuses; no second tab. | `dump_focused_tab_info` shows the same `fileID`. |
| E7 | Click a Local `.md` file (e.g. `docs/vision.md`). | New editable tab opens. ⌘S works. | `focused_doc_info` → `isReadOnly: false, origin.kind: "local"`. `dump_command_state` → `save: true, saveAs: true`. |

---

## §F — Token states

**Goal:** Each token state renders sensibly; nothing crashes.

| # | Token state | Expected sidebar |
|---|--------|----------|
| F1 | No token. | Only Local root visible (or empty state if no folder either). |
| F2 | Valid token. | PM root expands and loads. |
| F3 | Invalid token (random string). | PM root shows inline error: server 400 / invalid tenant. |
| F4 | Expired token. | PM root shows inline error: 401/403 → "Not signed in — set token in Debug menu". |
| F5 | Token rotated mid-session. | Setting a new token via Debug menu / harness `pm_token_set` fires `reconcileConnectors()`; PM root re-loads with the new identity. |

---

## §G — Regression sweep

**Goal:** D6/D14/D17 behaviors still work post-D18 refactor.

| # | Behavior | Reference | Pass criterion |
|---|--------|----------|---------------|
| G1 | Open Folder + sidebar tree (D6). | `docs/current_work/testing/d06_workspace_foundation_*` if present. | All D6 expectations hold. |
| G2 | Tabs: open, switch, close, persist across launch (D6). | D6 manual plan. | Same. |
| G3 | Save / Save As on a Local file (D14). | D14 manual plan. | ⌘S / ⌘⇧S work; atomic write; watcher reflects external edits. |
| G4 | Table rendering (D17 — TextKit 1). | D17 manual plan. | Tables render with correct grid; click-in-cell places caret natively. |
| G5 | Scroll / line numbers (D9–D11). | Their manual plans. | No regression. |

---

## Pass / Fail summary

| Section | Result | Notes |
|---|---|---|
| A — Sidebar structure | ✅ | Driven by harness through phase 3 commit `4d7d9cf` + visual smoke after phase 5. |
| B — Tree expansion | ✅ | Phase 3 + follow-up `58fbffc` (X-Tenant-ID header) verified expand/collapse cycle + cached re-expansion. |
| C — Cross-tenant badges | ✅ | Phase 4 commit `add6cd9`; 17 cross-tenant rows with correct E / RC / P initials and pink palette verified. |
| D — Unsupported rows | ✅ | Phase 1 + phase 4. `dump_sidebar_state` confirms `supported: false` for non-`.md`. |
| E — Read-only PM open | ✅ | Phase 5 commit `b659864`. `byteCount: 6638` from rockcut-site-guide.md; ⌘S/⌘⇧S correctly disabled. |
| F — Token states | ✅ | Phases 2 + 3; 400 invalid-tenant + workflow recovery via Debug menu both verified. |
| G — Regression | — | Visual confirmation per CD on 2026-04-27 ("This looks great"). |
