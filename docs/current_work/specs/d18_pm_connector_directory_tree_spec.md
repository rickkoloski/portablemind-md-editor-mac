# D18 — Workspace connector + PortableMind directory tree

**Status:** APPROVED FRAME — all four scope questions answered (see Decision log, 2026-04-27). Plan + prompt next.

**Trace:**
- `docs/vision.md` — Principle 1 (agentic HITL companion), Principle 3 (markdown today, structured formats tomorrow → connector seam needed).
- `docs/portablemind-positioning.md` — standalone-capable, PortableMind-aware; this is the first concrete PortableMind-aware deliverable.
- `docs/stack-alternatives.md` §3 abstraction #3 — "File-system abstraction" promised here gets its first protocol shape.
- `docs/engineering-standards_ref.md` — `accessibilityIdentifier` on every visible element; localizable strings for tree headers + badge tooltips.
- Memory `feedback_no_shortcuts_pre_users.md` — pre-user products build the hard thing right, no compat fallbacks.

**Position in roadmap:** First concrete slice of the long-parked **D7+ PortableMind integration umbrella**. First visible milestone: the west pane shows the PortableMind file/directory tree (or part of it), expandable, with cross-tenant share badges and file counts — visually consistent with the PM web app's "Shared Files" pane.

## Architecture

### Connector protocol

New `Connector` protocol abstracting storage backend — realizes "File-system abstraction" from `stack-alternatives.md` §3. Two implementations:

- **`LocalConnector`** — existing folder-tree code (`Sources/Workspace/FolderTreeModel.swift` etc.) refactored to fit the protocol. Behavior unchanged from a user POV.
- **`PortableMindConnector`** (new) — talks to Harmoniq REST.

Protocol surface (sketch — finalized in plan):

```swift
protocol Connector {
    var rootName: String { get }                       // "Local" | "PortableMind"
    func children(of path: String) async throws -> [ConnectorNode]
    func openFile(at path: String) async throws -> Data        // read-only for D18
}

struct ConnectorNode {
    let id: String
    let name: String
    let path: String
    let kind: Kind                  // .directory | .file
    let fileCount: Int?             // dirs only
    let tenant: TenantInfo?         // PM-side; nil for local
    enum Kind { case directory, file }
}

struct TenantInfo {
    let id: Int
    let name: String                    // e.g. "Istonish Prod Support"
    let enterpriseIdentifier: String    // e.g. "RC"
}
```

### PortableMindConnector — API contract

- **List a directory level:** `GET /api/v1/llm_directories?parent_path=/<path>&cross_tenant=true&limit=-1`
  - Response includes `id`, `name`, `path`, `parent_path`, `depth`, `file_count`, `subdirectory_count`, `tenant_id`, `tenant_enterprise_identifier`, `tenant_name`.
  - Lazy load: children-on-expand (matches PM frontend pattern in `harmoniq-frontend/src/apps/file-artifact/components/DirectoryTree.tsx`).
- **List files in a directory:** `GET /api/v1/llm_files?directory_path=<path>`
- **Fetch file content:** ActiveStorage signed URL on the LlmFile record (D18 fetches read-only for `.md` files only).
- **Auth:** Bearer token from Keychain. Token is manually seeded for dev (sign-in UI is a separate downstream deliverable). Token storage uses `Sources/Auth/KeychainTokenStore.swift` (new).

### Cross-tenant model

Every node from PM carries `tenant_id` + `tenant_enterprise_identifier` + `tenant_name`. The current user's tenant comes from a `/api/v1/me` call (or equivalent — final endpoint chosen in plan). Badge appears when `node.tenant_id ≠ user.tenant_id`.

## Sidebar tree UI

- **Finder-style multi-connection sidebar** (per Q2 decision):
  - **Local** root — existing tree behavior, unchanged.
  - **PortableMind** root — new, lazy-load on expand. Manually configured for D18 (one connection, Keychain token); the create-connection UX is **D19 — Connection-management UX**.
  - Roots stack vertically; user can collapse either.
- **File visibility** (per Q1 decision):
  - Directories — always shown.
  - Supported files (`.md` for D18) — active rows, clickable.
  - Unsupported file types — shown by name but **disabled** (grayed); hover tooltip: "file type not supported." Keeps the directory contents complete and discoverable while the editor's actionable surface stays unambiguous.
- **Cross-tenant badge** — small pill (16pt) with 1–2-char tenant initials (first letter, or first letters of first two words of `tenant_name`). Colors mirror PM web (`#FCE4EC` bg, `#E5007E` fg) for visual continuity across the ecosystem. Tooltip on hover shows full `tenant_name`.
- **File-count caption** next to folder name when `file_count > 0`. Same typography as the PM web app.
- **Loading state** — expand chevron shows a small spinner while children are fetching.
- **Error state** — token expired / network error → inline error row with retry.

## Open questions

**Question:** Tree contents — dirs-only (mirrors PM's split DirectoryTree + FileTable), or merged dirs + `.md` files in one tree (Finder / VS Code / Sublime model)? Recommend **merged**: code-editor mental model dominates our users; PM's two-pane split is responsive-web-driven and we don't carry that constraint. (Filter to `.md` for D18; widen later via the document-type registry.)

rak: should show dirs, markdown files, and names of unsupported files, but grayed out and deactivated with hover text "file type not supported".

**Question:** Connector refactor scope — define the protocol AND port the existing local tree to it now, or land PM-only and port local later? Recommend **port now**: `feedback_no_shortcuts_pre_users.md` says build the hard thing right; local tree code is small, and shaping the protocol against two real implementations is the only way to find the right seams.

rak: I was thinking that we'd follow a similar pattern to the Mac Finder, where you can see local and remote connections in the left tree. There would also need to be a new UX to create connections, again with a workflow similar to the Finder app, but focused on MCP connections.

**Question:** Open-on-click — strictly tree-visualization, or include read-only file open (click `.md` → open in editor tab, no save-back yet)? Recommend **include read-only open**: closes the loop end-to-end, tests more of the connector contract, more demo-able. Write-back becomes a clean next deliverable.

rak: we can take this in any scope tranches that make sense, but we will definitely want save back in an eventual release.

**Question:** Auth — Keychain-seeded API token for dev (5-min setup) for now, with sign-in UI as a downstream deliverable? Recommend **yes**: auth UI is real work and not the current bottleneck.

rak: agreed on both initial and eventual scope

## Decision log

| Date | Decision | Decided by |
| --- | --- | --- |
| 2026-04-27 | **Tree contents** (Q1): show directories + supported files (`.md` initially) as active rows; unsupported file types render as **disabled** rows with hover tooltip "file type not supported." Lets users see the full directory contents while making editor-supported files visually distinct. | RAK |
| 2026-04-27 | **Connector model** (Q2): Mac Finder-style sidebar with multiple connections (Local + MCP-based remote connections). The connection-creation UX (Finder-like "Connect to Server" workflow, focused on MCP) is split out as **D19 — Connection-management UX**. D18 stays scoped to: connector protocol, Local connector, one PortableMind connection (manually configured), tree UI, read-only open. | RAK |
| 2026-04-27 | **Open-on-click** (Q3): read-only file open ships in D18. Save-back is **committed for a future release** (not indefinitely deferred); slotted as a deliverable after D19 once the connection-management UX is in place. | RAK |
| 2026-04-27 | **Auth** (Q4): Keychain-seeded API token for dev in D18; sign-in UI is a downstream deliverable that travels with D19's connection-management UX. | RAK |


## Out of scope (deliverables that follow D18)

- **D19 — Connection-management UX.** Finder-style "Connect to MCP server" workflow: add/edit/remove connections, sign-in UI, OAuth or token paste, token refresh. D18 ships with a single manually-configured PortableMind connection.
- **Write-back to PortableMind** (save → API). Committed for a future release; slotted after D19.
- Search across the PM tree.
- Non-`.md` file viewers (CSV, image, PDF, etc.) — D18 shows them as disabled rows.
- File detail / metadata side panel.
- Drag-and-drop between Local and PortableMind roots.

## Acceptance criteria (provisional — finalized in plan after open questions resolve)

1. App launches; west pane shows two roots: **Local** (existing behavior) + **PortableMind**.
2. Expanding **PortableMind** fetches root directories from Harmoniq and renders them with chevrons (where `subdirectory_count > 0`).
3. Cross-tenant directories show the tenant initials badge in the PM color palette; tooltip reveals the full tenant name.
4. Folder file-counts appear next to folder names where `file_count > 0`.
5. Click on a `.md` file → opens in a new tab, read-only (per Q3 decision).
8. Non-`.md` files appear in the tree as disabled rows; hover tooltip reads "file type not supported" (per Q1 decision).
6. Token refresh / expiry surfaces a friendly error row with retry.
7. Manual test plan at `docs/current_work/testing/d18_*_manual_test_plan.md` covers all of the above.