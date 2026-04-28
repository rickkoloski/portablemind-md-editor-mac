# D18 Plan — Workspace connector + PortableMind directory tree

**Spec:** `docs/current_work/specs/d18_pm_connector_directory_tree_spec.md`
**Created:** 2026-04-27

---

## 0. Approach

Six phases, each independently buildable and runnable:

1. **Connector protocol + LocalConnector port** — protocol shape, refactor existing local tree into the protocol's first implementation. No behavior change for the user.
2. **PortableMind API client + Keychain token store** — pure infrastructure; no UI. Verifiable from a debug menu / unit test against a seeded token.
3. **PortableMindConnector + multi-root sidebar** — wire the API client behind the protocol; sidebar grows a second root labeled "PortableMind" that lazy-loads on expand.
4. **Cross-tenant badge + unsupported-file disabling** — visual polish + Q1 implementation (greyed disabled rows for non-`.md`).
5. **Read-only file open** — click `.md` on the PM tree → fetch content → open in a new editor tab marked read-only. (Q3 implementation.)
6. **Manual test plan + COMPLETE + roadmap update** — ship docs; flip D18 to ✅ in `roadmap_ref.md`.

Each phase ends in a commit. Stop and surface a `**Question:**` to CD if a phase reveals scope drift; don't paper over with workarounds (ref `feedback_no_shortcuts_pre_users.md`).

---

## 0.1 Verification approach (harness-first)

Per `Sources/Debug/HarnessCommandPoller.swift` — the project's debug-build JSON-file IPC harness — D18 verifies **primarily through extended harness actions, not XCUITest**. The harness keeps focus wherever the user puts it; CC and CD can both work in parallel windows while regression sweeps run. XCUITest grabs input focus and is currently brittle (see i03).

**Stack split for D18:**

- **Harness actions** — primary regression surface. Each phase below lists the actions it adds. Assertions read JSON result files via `Bash cat | jq` from CC's session, no app focus needed.
- **XCUITest** — single launch-smoke per area. The current 3 failing tests (i03) get fixed in phase 6 alongside the manual test plan. Do **not** block phases 1–5 on these; they assert reachability, not behavior, and the behavior surface is the harness.
- **Manual test plan** — phase 6 deliverable; mirrors the harness action list with human-readable steps so a non-CC tester can reproduce.

**Action conventions** (extending the harness):
- New actions slot into `HarnessCommandPoller.dispatch(action:params:)` (search `TEST-HARNESS:` markers in the source for every accommodation made for testing).
- Result files write atomically to `/tmp/mdeditor-<topic>.json`.
- File-disappearance of `/tmp/mdeditor-command.json` is the completion signal (D14/D15 contract — no sleeps in the driver).
- `dump_*` actions are read-only; verbs that mutate state are imperative (`expand_*`, `open_*`, `collapse_*`).

**i03 (pre-existing XCUITest failures):** the three failing tests look for `md-editor.main-editor` accessibility identifier on launch, but the empty-editor placeholder mounts when no document is open. Phase 6 either (a) opens a doc in setUp before asserting, or (b) adds a shadow identifier on the empty-editor placeholder. Pick during phase 6.

---

## Phase 1 — Connector protocol + LocalConnector port

**Goal:** introduce the protocol; refactor the existing local tree to implement it. User-visible behavior unchanged.

**New files:**

- `Sources/Connectors/Connector.swift` — protocol + `ConnectorNode` + `TenantInfo` value types per spec § Architecture.
- `Sources/Connectors/LocalConnector.swift` — wraps the existing `FolderTreeLoader` logic; root is the workspace folder URL chosen by the user (existing D6 behavior). Returns `ConnectorNode` values with `kind = .directory|.file`, `tenant = nil`, `fileCount = nil` (we don't compute file counts for local — MAYBE add later via async size-of-dir; out of scope for D18).

**Files updated:**

- `Sources/Workspace/FolderTreeModel.swift` — replace direct `FolderNode` use with a protocol-driven model. The model now holds `[Connector]`; node hierarchy is rendered as connector-rooted subtrees.
- `Sources/App/<sidebar view>` — sidebar `OutlineGroup` driven by `ConnectorNode` instead of `FolderNode`. Connector identity (Local vs. PM) determines the root row label and icon.
- `Sources/Workspace/FolderTreeWatcher.swift` — keep wiring; LocalConnector vends children synchronously (filesystem is fast enough), watcher continues to invalidate on filesystem events.

**Protocol shape (final, ratifies spec sketch):**

```swift
protocol Connector: Sendable {
    /// Stable label for the root row in the sidebar. e.g. "Local" or "PortableMind".
    var rootName: String { get }

    /// SF Symbol name (or asset name) for the root row icon.
    var rootIconName: String { get }

    /// Children of the directory at `path`. Path semantics are connector-defined;
    /// `""` (or `nil`) means "root". For LocalConnector, paths are URL.path strings
    /// rooted at the workspace folder. For PortableMindConnector, paths follow the
    /// LlmDirectory `path` field convention (`/`, `/projects`, `/projects/2024`, …).
    func children(of path: String?) async throws -> [ConnectorNode]

    /// Read file content. D18 calls this only for `.md` paths; connectors may
    /// throw `ConnectorError.unsupported` for other types.
    func openFile(at path: String) async throws -> Data
}

struct ConnectorNode: Identifiable, Hashable {
    let id: String                  // connector-scoped unique id
    let name: String
    let path: String                // pass back to `children(of:)` to expand
    let kind: Kind
    let fileCount: Int?             // dirs only; nil if not known
    let tenant: TenantInfo?         // nil for local
    let isSupported: Bool           // .md → true; other types → false (Q1)

    enum Kind: Hashable { case directory, file }
}

struct TenantInfo: Hashable {
    let id: Int
    let name: String                    // "Istonish Prod Support"
    let enterpriseIdentifier: String    // "RC"
}

enum ConnectorError: Error {
    case unsupported(String)
    case unauthenticated
    case network(Error)
    case server(status: Int, message: String?)
}
```

**DOD:**
- App builds, launches, opens existing local workspace folder.
- Sidebar shows a single root labeled "Local" (matches D6 behavior; renaming acceptable since multi-root is the new model).
- Expanding a folder loads children unchanged from D6.
- All existing UITests pass.
- Manual smoke: open a folder via `File → Open Folder`, navigate, click a `.md`, opens in tab. No regressions.

**Commit:** `D18 phase 1 — introduce Connector protocol; port LocalConnector`

---

## Phase 2 — PortableMind API client + Keychain token store

**Goal:** infrastructure-only. No UI. After this phase you can fetch tree data from Harmoniq with a seeded token and log results, but no sidebar wiring yet.

**New files:**

- `Sources/Auth/KeychainTokenStore.swift` — read/write a single bearer token to the macOS Keychain under a fixed service identifier (`ai.portablemind.md-editor.harmoniq-token`). Methods: `save(token:)`, `load() throws -> String?`, `clear()`.
- `Sources/Connectors/PortableMind/PortableMindAPIClient.swift` — `URLSession`-backed; bearer auth; methods:
  - `listDirectories(parentPath: String?, crossTenant: Bool = true) async throws -> [DirectoryDTO]`
  - `listFiles(directoryPath: String) async throws -> [FileDTO]`
  - `fetchFileContent(fileID: Int) async throws -> Data` (resolves the ActiveStorage signed URL from `LlmFile.file_data` or via a dedicated endpoint — finalize in implementation; the harmoniq research notes both paths exist).
  - `currentUserTenantID() async throws -> Int` (calls `/api/v1/me` or equivalent — confirm endpoint during impl; needed for the cross-tenant badge predicate).
- `Sources/Connectors/PortableMind/PortableMindAPITypes.swift` — Codable DTOs: `DirectoryDTO`, `FileDTO`, `MeDTO`. Direct mirrors of Harmoniq response shapes.
- `Sources/Connectors/PortableMind/PortableMindEnvironment.swift` — base URL config. Defaults to `https://www.dsiloed.com/api/v1` (per memory `harmoniq_mcp_points_at_prod.md`); overridable via `UserDefaults` key `PortableMindBaseURL` for dev pointing at localhost / staging.

**Files updated:**

- `project.yml` — add a new "PortableMind base URL" build setting? No — keep config in UserDefaults so dev users can switch without rebuild.
- `Sources/App/AppMenu.swift` (or equivalent) — add a `Debug → Set PortableMind Token…` menu item that prompts for a token and writes it to Keychain (debug build only). This is the dev seeding mechanism for D18; D19 replaces with sign-in UI.

**Token seeding (developer instructions, captured in COMPLETE):**

```bash
# One-time, until D19 sign-in UI lands.
# 1. Sign in to Harmoniq web UI as your test user.
# 2. Pull the bearer token from devtools (Network tab → Authorization header) or from `localStorage.token`.
# 3. App: Debug menu → "Set PortableMind Token…" → paste.
# 4. Or, command line: security add-generic-password -s "ai.portablemind.md-editor.harmoniq-token" -a "default" -w "<token>"
```

**Harness actions added** (Phase 2):
- `pm_api_smoke` → `{path: "/tmp/mdeditor-pm-api.json"}` — calls `listDirectories(parentPath: nil)`, writes the raw response (or error envelope) so CC can `cat | jq` and verify shape.
- `pm_token_set` → `{token: "..."}` — writes to Keychain via the same path the Debug menu would.
- `pm_token_dump` → `{path: "/tmp/mdeditor-pm-token.json"}` — emits `{present: bool, length: Int}` (never the token itself).

**DOD:**
- `pm_api_smoke` against a localhost Harmoniq with a seeded test-tenant token returns directories matching `seed.rb` fixture state. Run from CC via `Bash`: write command JSON, wait for `/tmp/mdeditor-command.json` to disappear, `cat /tmp/mdeditor-pm-api.json`, assert.
- `pm_token_set` + `pm_token_dump` round-trip correctly.
- App builds and launches; no UI changes visible without the Debug menu open.
- No PII / token logging in release builds (release build excludes the harness via `#if DEBUG`).

**Commit:** `D18 phase 2 — PortableMind API client + Keychain token store`

---

## Phase 3 — PortableMindConnector + multi-root sidebar

**Goal:** the visible milestone. Sidebar shows Local + PortableMind roots. Expanding PortableMind fetches and displays the directory tree.

**New files:**

- `Sources/Connectors/PortableMind/PortableMindConnector.swift` — implements `Connector` using `PortableMindAPIClient`. Holds the cached `currentUserTenantID` for badge predicates. Maps DTOs → `ConnectorNode`s. Sets `isSupported = true` only for `.md` files (Q1).

**Files updated:**

- `Sources/Workspace/FolderTreeModel.swift` — `connectors` is now `[LocalConnector(workspaceURL: …), PortableMindConnector(apiClient: …)]`. Persistence: store enabled-connectors in UserDefaults so the user's PM-enabled state persists across launches.
- Sidebar view — render each connector as its own root. Each root expands lazily to fetch children via `connector.children(of: nil)`. Children of children flow the same way.
- `Sources/Files/ExternalEditWatcher.swift` — no change in this phase; watcher only operates on local files. PM file watching is out of scope for D18.

**Loading + error UI:**

- Expand chevron shows a small spinner while `children(of:)` is in flight.
- On `ConnectorError.unauthenticated` → row text becomes "Not signed in — set token in Debug menu" (D19 will replace with proper UI).
- On `ConnectorError.network` → "Couldn't reach PortableMind" with a retry chevron.

**Harness actions added** (Phase 3):
- `dump_sidebar_state` → `{path: "/tmp/mdeditor-sidebar.json"}` — emits `{roots: [{connectorID, rootName, expanded, children: [...]}]}`. Recursive: only loaded subtrees are emitted; unloaded subtrees show `{loaded: false}`. Lets CC verify sidebar state without focusing the window.
- `expand_sidebar_path` → `{connectorID, path}` — programmatically expands a node; triggers async load. Idempotent.
- `collapse_sidebar_path` → `{connectorID, path}` — collapses; preserves cache.
- `dump_connector_tree` → `{connectorID, parentPath, path: "/tmp/mdeditor-connector-tree.json"}` — bypasses UI, calls `connector.children(of: parentPath)` directly. Lets CC distinguish API-level failure from UI-level failure.

**DOD:**
- Sidebar shows two roots: **Local** (existing tree) + **PortableMind**.
- `dump_sidebar_state` shows two roots with `connectorID = "local"` and `connectorID = "pm.<connection-id>"`.
- `expand_sidebar_path {connectorID: "pm…", path: "/"}` → `dump_sidebar_state` shows root directories with chevrons where `subdirectory_count > 0`.
- Drilling three levels deep via repeated `expand_sidebar_path` succeeds; `collapse_sidebar_path` followed by re-expand returns from cache (no second network call — verifiable via Harmoniq access log or a `pm_api_call_count` action if useful).
- Network errors / missing-token states render as inline rows; `dump_sidebar_state` reflects them (`error: "..."` field on the affected node) — not crashes.

**Commit:** `D18 phase 3 — PortableMindConnector + multi-root sidebar`

---

## Phase 4 — Cross-tenant badge + unsupported-file disabling

**Goal:** visual parity with PM web for cross-tenant rows; Q1 unsupported-file behavior.

**New files:**

- `Sources/UI/TenantInitialsBadge.swift` — small NSView (or SwiftUI view) that renders a 16pt pill with 1–2-char tenant initials. Initials algorithm matches `harmoniq-frontend/src/components/shared/TenantInitialsBadge.tsx` (first letter for single-word names; first letters of first two words for multi-word; uppercase). Background `#FCE4EC`, foreground `#E5007E`. Tooltip = `tenant.name`.

**Files updated:**

- Sidebar row view — when `node.tenant != nil && node.tenant.id != currentUserTenantID`, mount the badge to the right of the node name (before the file-count caption).
- Sidebar row view — when `node.kind == .file && !node.isSupported`:
  - Render row text in `NSColor.disabledControlTextColor`.
  - Disable click handler (no `openFile` call).
  - `toolTip = "file type not supported"` (localizable string).

**Harness actions added / extended** (Phase 4):
- `dump_sidebar_state` (extended) — each node now includes `{tenantBadge: {initials, tooltip, fgHex, bgHex} | null, supported: bool}`. Lets CC assert badge presence/absence + correct initials per row from a JSON dump.

**DOD:**
- Cross-tenant rows in PM tree show pill badges with correct initials and colors. Verifiable via `dump_sidebar_state`: assert `tenantBadge.initials == "RC"` for a known cross-tenant row in the test fixture.
- Same-tenant rows have `tenantBadge: null`.
- Non-`.md` files appear in the tree but `supported: false`. Hover tooltip "file type not supported" — verified manually in phase 6 (tooltips are AppKit-managed and not introspectable from the harness without screen-grabs).
- Accessibility: badge has `accessibilityLabel = "shared from <tenant.name>"`; disabled file row uses `accessibilityRole = .staticText` instead of button. Verifiable via the existing `window_info` action.

**Commit:** `D18 phase 4 — cross-tenant badges + unsupported-file disabled rows`

---

## Phase 5 — Read-only file open from PortableMind

**Goal:** click a `.md` file in the PM tree → opens in a new editor tab in **read-only** mode. Save commands are disabled while the tab is read-only.

**New files (likely):**

- `Sources/Editor/EditorDocument+ReadOnly.swift` — extends `EditorDocument` with an `isReadOnly: Bool` flag and an "origin" descriptor (`.local(URL)` or `.portableMind(connector: PortableMindConnector, path: String, fileID: Int)`).

**Files updated:**

- `Sources/Workspace/TabStore.swift` — opening a PM file creates a tab with `isReadOnly = true` and the PM origin.
- `Sources/Editor/LiveRenderTextView.swift` — when `isReadOnly`, the view's `isEditable = false`. (Selection + scroll still work.)
- `Sources/App/AppMenu.swift` — `⌘S` and `⌘⇧S` disabled when the focused tab is read-only.
- Sidebar row tap handler — `connector.openFile(at: node.path)` returns `Data`; pass to `TabStore.open(content:origin:)`.
- Tab UI — read-only tabs show a small "READ-ONLY" pill near the title. Disambiguates from local-editable tabs.

**Edge cases:**

- Token expired mid-fetch → present a non-blocking inline alert in the tab area; close the tab.
- File too large (> 1 MB threshold? — confirm in implementation) → defer with a friendly "preview not supported for files of this size" message; this is a graceful-degradation case, not a regression.
- Encoding: PM files are stored as UTF-8 per markdown convention; assume UTF-8, fall back to UTF-16 LE BOM detection if needed.

**Harness actions added** (Phase 5):
- `connector_open_file` → `{connectorID, path}` — programmatically triggers the same flow as a row click; the `connectorID` lets us drive Local vs. PortableMind opens uniformly.
- `dump_focused_tab_info` (extended from `focused_doc_info`) — adds `{readOnly: bool, origin: "local" | "portablemind", connectorID, sourcePath}` so CC can assert read-only state and origin without inspecting AppKit.
- `dump_command_state` → `{path: "/tmp/mdeditor-commands.json"}` — emits enabled/disabled state of menu commands `save`, `saveAs`. Verifies ⌘S correctly greys for read-only tabs.

**DOD:**
- `connector_open_file {connectorID: "pm…", path: "<file>"}` opens a new tab; `dump_focused_tab_info` reports `readOnly: true, origin: "portablemind"`.
- `dump_command_state` reports `save: false, saveAs: false` while the read-only tab is focused; flips to `save: true` when a Local tab is focused.
- `set_text` action against a read-only tab is a no-op (or emits a warning that doesn't mutate); subsequent `dump_state` shows storage unchanged.
- External-edit watcher: `dump_focused_tab_info.watcherActive` is `false` for PM tabs, `true` for Local tabs.
- Manual: closing the tab doesn't leak the connector reference (Instruments leak detection in phase 6).

**Commit:** `D18 phase 5 — read-only file open from PortableMind connector`

---

## Phase 6 — Manual test plan + COMPLETE + roadmap update

**Goal:** docs ship; D18 marked ✅.

**New files:**

- `docs/current_work/testing/d18_pm_connector_directory_tree_manual_test_plan.md` — sections:
  - **§A** Sidebar structure (multi-root, Local unchanged, PortableMind present)
  - **§B** PM tree expansion (lazy load, deep nav, error states)
  - **§C** Cross-tenant badges (correct initials, colors, tooltip; absent for same-tenant)
  - **§D** Unsupported file rows (greyed; tooltip; click is no-op)
  - **§E** Read-only file open (open .md, edit blocked, save disabled, pill visible)
  - **§F** Token states (no token, expired token, valid token)
  - **§G** Regression: D6 local tree, D14 save, D17 table rendering all still work
- `docs/current_work/stepwise_results/d18_pm_connector_directory_tree_COMPLETE.md` — completion record per template; calls out D19 as the explicit next deliverable.

**Files updated:**

- `docs/roadmap_ref.md` — D18 → ✅ Complete; add row for D19 — Connection-management UX (status: Pending).
- `docs/engineering-standards_ref.md` — append a section about connector-driven trees if any new standard surfaced (e.g., "every Connector implementation must surface its root in the sidebar with a stable accessibilityIdentifier of the form `connector-root.<rootName>`").
- `UITests/LaunchSmokeTests.swift` (and the two MutationTests) — fix i03 by either opening a fixture doc in `setUp()` before asserting on `md-editor.main-editor`, OR adding a shadow accessibilityIdentifier on the empty-editor placeholder so the launch state is testable directly. Pick whichever has lower change surface.

**DOD:**
- All sections of the manual test plan walked through; results recorded.
- COMPLETE doc references the test plan, lists findings, and includes the dev token-seeding instructions.
- Roadmap reflects D18 ✅ and D19 queued.
- i03 closed: `xcodebuild test` reports 0 failing UITests. Mark i03 as `Fixed` in `docs/issues_backlog.md`.
- Final commit; push only after CD review.

**Commit:** `D18 phase 6 — manual test plan, COMPLETE doc, roadmap update`

---

## Risks / open implementation questions

1. **`/api/v1/me` endpoint shape.** Harmoniq research surfaced the cross-tenant predicate but didn't pin the exact endpoint name. Confirm in phase 2; if absent, derive from token introspection or a `/api/v1/sessions/current` analogue.

2. **File-content fetch path.** Two paths exist (LlmFile.file_data JSONB vs. ActiveStorage signed URL). Pick one in phase 2; document in COMPLETE.

3. **Base URL default.** Memory says Harmoniq MCP points at prod; for D18 we likely want **localhost** as the default during development (so we don't hit production data while building). Final default is a Q for CD before phase 2 commits.

4. **File counts on local.** `ConnectorNode.fileCount` is nil for local. Mild visual inconsistency (PM dirs show counts, Local dirs don't). Acceptable for D18; revisit if it confuses users.

5. **Tab persistence across launch.** PM read-only tabs reference a remote file by ID. If we restore tabs across launches (D6 behavior for local), do we re-fetch PM tabs? Default: drop PM tabs on relaunch, restore local only. Confirm in phase 5.
