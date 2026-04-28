# D19 — PortableMind save-back

**Status:** APPROVED FRAME — all four scope questions answered (see Decision log, 2026-04-27). Plan + prompt next.

**Trace:**
- `docs/vision.md` — Principle 1 (agentic HITL companion). The dogfood `**Question:**` → `**Decision:**` loop currently only works on local files; PM-stored docs are read-only after D18 phase 5. Save-back closes that gap.
- `docs/portablemind-positioning.md` — moves the editor from "PortableMind-aware" to "actively dogfooding the PortableMind storage surface."
- `docs/stack-alternatives.md` §3 abstraction #3 — extends the Connector protocol's contract.
- `docs/engineering-standards_ref.md` §3.1 — branching: lands on `feature/d19-pm-save-back`.
- D18 spec Decision log (2026-04-27) — D19/D20 ordering swap; save-back ahead of connection-management.
- Memory `feedback_no_shortcuts_pre_users.md` — pre-user products build the hard thing right.

**Position in roadmap:** D19 — first deliverable on `feature/d19-pm-save-back` cut from `main` after D18 merged. Unblocks human↔agent dogfooding on PortableMind-stored docs. D20 (connection-management UX) follows.

---

## Why now (over connection-management)

D18 phase 5 ships read-only file open from PortableMind. The agentic editing loop (CC drops `**Question:**` → human answers inline → CC logs `**Decision:**` in the table) currently works only on local files. A user with PM-resident roadmap / spec / decision-log docs gets to *read* the editor's render of them but can't run the loop on them — every save attempt no-ops. Save-back unlocks the editor's central use case for PM users.

Connection-management UX (D20) replaces the dev-only Debug menu's *Set PortableMind Token…* affordance, but token paste is acceptable for solo developer use. Save-back is not — read-only PM docs are user-facing dead-end.

---

## Architecture

### Connector protocol additions

```swift
protocol Connector: AnyObject, Sendable {
    // ... existing ...

    /// Whether this connector supports writing back to `node`. UI uses
    /// this to decide whether a tab should be editable; PM tabs may
    /// flip from read-only to editable when the user has write
    /// capability + the connector is online + the file's tenant
    /// permits cross-tenant write.
    func canWrite(_ node: ConnectorNode) -> Bool

    /// Persist `bytes` as the new content of `node`. Throws on error;
    /// returns the resulting `ConnectorNode` so callers can pick up
    /// any server-assigned values that changed (a fresh signed URL on
    /// PM, a new mtime on Local, etc.).
    func saveFile(_ node: ConnectorNode, bytes: Data) async throws -> ConnectorNode
}
```

`canWrite` is synchronous so the UI can ask cheaply on tab open / focus. `saveFile` is async (network on PM; even Local goes through the protocol's async surface).

`ConnectorError` grows two cases:

- `case storageQuotaExceeded(String)` — Harmoniq returns 402 with `DOCUMENT_STORAGE_LIMIT_EXCEEDED` when the tenant is over storage quota; surface this distinctly so the UI can present a useful message rather than the generic server error.
- `case writeForbidden(String)` — explicit write-permission failure (401/403 on PUT); distinct from `unauthenticated` so we can keep read-only browsing alive while save-back is denied.

### LocalConnector.saveFile

Mirrors `EditorDocument.save` (D14): pause the watcher, write atomic UTF-8, restart the watcher. Returns a fresh `ConnectorNode` with the same id (path is unchanged).

### PortableMindConnector.saveFile

`PATCH /api/v1/llm_files/:id` with multipart form-data. `llm_file[file]` is the new content as a file part with `text/markdown` content-type. Bearer + `X-Tenant-ID` headers as for read.

Response is the standard `{success, llm_file: {url, ...}}` envelope; the `url` is a fresh 20-minute signed URL. No conflict-detection on the server (pure last-writer-wins) — D19 client-side adds optimistic detection (see Q2).

PortableMindAPIClient grows:
- `updateFile(fileID:bytes:contentType:) async throws -> FileDTO`

PortableMindConnector parses fileID from `node.id` (same pattern as `openFile`), calls the API client, returns a refreshed `ConnectorNode`.

### EditorDocument changes

- `isReadOnly` becomes a **runtime flag** (currently a `let` set at init): `@Published var isReadOnly: Bool`. Defaults driven by origin + connector capability:
  - `.local` → false (always editable)
  - `.portableMind(...)` → starts false IF the connector reports `canWrite(node) == true`, else true.
- New `save()` path: when `origin == .portableMind`, route through `connector.saveFile` rather than the local writeAndRewatch.
- New `SaveError.writeForbidden`, `.storageQuotaExceeded`, `.networkSaveFailed` cases mirroring the connector error vocabulary.

### TabBarView

- "READ-ONLY" pill stays for tabs where the connector reports `canWrite == false` or the connector is offline.
- A subtle "saving…" state (small spinner near the close button) shows while a save is in flight.

### EditorContainer

`textView.isEditable = !document.isReadOnly` is already wired in D18; needs to become reactive to `document.$isReadOnly` changes (subscription in `wireDocumentSubscription`).

---

## Open questions

**Question:** **Save semantics.** Save-on-⌘S (current local behavior, simplest, predictable) or auto-save-on-blur (closer to web-native PortableMind UX, but introduces save-while-typing race conditions and dirty-state ambiguity)? Recommend **save-on-⌘S only for D19** — matches D14 local behavior, keeps the dirty-flag model simple. Auto-save can land as a separate deliverable once we have telemetry on how often users forget to ⌘S on a PM tab.

rak: let's start with Save-on-Cmd+S

**Question:** **Conflict resolution.** Last-writer-wins on the server means simultaneous edits from another agent / web UI silently overwrite. Three options: (a) **server-wins prompt** — before each save, GET the current `updated_at` and reject if newer than the version we read; show a "remote has changed, overwrite?" dialog; (b) **client-wins blind** — write and pray; (c) **three-way merge** — out of scope for D19. Recommend **(a) server-wins prompt** — the GET-before-save adds one round-trip but avoids silent data loss. Three-way merge becomes its own future deliverable.

rak: what about a warning? file has changed, overwrite? (if not feasible then last wins)

**Question:** **Save UX during in-flight requests.** Three options: (a) **optimistic** — keep editing while save flies; if save fails, surface a non-blocking error and keep the dirty buffer; (b) **pessimistic** — lock the editor while saving (small modal-ish "saving…" with a cancel option); (c) **debounced** — batch keystrokes and save every N seconds. Recommend **(a) optimistic** — pessimistic is the worst feel for fast typers, and debounced is auto-save in disguise (Q1 already says no auto-save).

rak: I'll go with your recommendation here

**Question:** **Rename / move on Save As.** Local Save As (D14) writes to a new URL; the document's `url` updates. PM "Save As" could PATCH `title` + `directory_path` (in-place rename) OR POST a new file (clone). Recommend **out of scope for D19** — Save As on a PM tab throws a `.unsupported` error with a hint message ("Save As for PortableMind documents is not yet supported; use the PortableMind web UI to rename or move"). The `Connector.saveFile` semantics for D19 are *replace contents only*. PM-side renames land as a future deliverable.

rak: future feature. We would like to eventually support save as, as well as new file, saved to a specified location.

---

## Decision log

| Date | Decision | Decided by |
| --- | --- | --- |
| 2026-04-27 | **Save semantics** (Q1): save-on-⌘S only. Auto-save deferred to a future deliverable; D14's dirty-flag model carries forward to PM tabs. | RAK |
| 2026-04-27 | **Conflict resolution** (Q2): server-wins **warning** before overwrite. Implementation: GET the current `updated_at` immediately before the PATCH; if the server's value is newer than the version we last saw, present a dialog ("This file changed on PortableMind since you opened it. Overwrite anyway?") with Overwrite / Cancel. **Graceful fallback:** if the GET-before-save round-trip itself fails (network blip, server error), default to writing through (last-writer-wins) so a flaky network doesn't block saves. The dialog is the firm protection; the fallback honors the realistic field condition. | RAK |
| 2026-04-27 | **Save UX during in-flight save** (Q3): optimistic — keep the editor responsive while the save flies, surface non-blocking error on failure, keep the dirty buffer. | RAK |
| 2026-04-27 | **Save As / rename / move on PM tabs** (Q4): out of scope for D19; ⌘⇧S on a PM tab presents an unsupported-feature dialog with a "future feature" hint. **Future commitment:** Save As (rename / move within PM) AND New File (create-at-target-location) are committed for a future deliverable — not just deferred indefinitely. Frame these as a unified deliverable on the post-D19 backlog. | RAK |


---

## Out of scope (deliverables that follow D19)

- **D20 — Connection-management UX.** Per the D18 Decision log re-ordering. Replaces the Debug menu's *Set PortableMind Token…* with a Finder-style add-connection flow.
- **PM file management — Save As + New File at target location.** Committed for a future deliverable (Q4 decision). Bundles three behaviors: rename a PM file in place; move a PM file to a different directory; create a new PM file at a chosen directory. Likely lands as one focused deliverable post-D20 since all three share the same connector / API surface.
- **Auto-save / debounced save** for PM tabs (Q1 deferral).
- **Three-way merge** for concurrent edits (Q2 deferral). The server-wins warning is the D19 protection.
- **Per-document share / permissions UI** (the editor reflects what the API allows; doesn't grant or revoke).
- **Offline queue** (save-while-disconnected, replay on reconnect). D19 surfaces network errors but doesn't queue retries.
- **Projects-app routing** (D21+) — semantic integration on top of save-back.

---

## Acceptance criteria (provisional — finalized in plan after open questions resolve)

1. Click a `.md` file in the PortableMind tree → tab opens **editable** (no READ-ONLY pill) when the connector reports `canWrite(node) == true`.
2. Type in a PM tab → buffer accepts edits.
3. ⌘S on a PM tab → connector PATCHes the file; tab shows a brief "saving…" indicator; on success, no error; on failure, an error sheet with retry.
4. Concurrent-edit detection (per Q2 decision): if the server's `updated_at` is newer than the version we read, prompt before overwriting.
5. (Pending Q4) Save As on a PM tab → unsupported-error with hint.
6. ⌘⇧S behavior matches Q4 decision.
7. Permission-denied / quota-exceeded responses surface distinctly from generic network errors.
8. Manual test plan at `docs/current_work/testing/d19_*_manual_test_plan.md` covers all of the above.
9. Harness actions (`pm_save_smoke`, extended `dump_focused_tab_info` to include `dirty` + `saving` state) verify the loop without focus-stealing.

---

## Risks / open implementation questions

- **Multipart upload from URLSession.** Swift doesn't have a built-in multipart builder; we'll write a small `MultipartFormDataBuilder` in `Sources/Connectors/PortableMind/` (~50 LOC). Tested against the existing harness path before integration.
- **`updated_at` timestamp echo.** The server-wins prompt (Q2 recommendation) requires the client to remember the version's `updated_at` from the open path so it can compare on save. ConnectorNode can carry an optional `lastSeenUpdatedAt: Date?` field.
- **Read-only fallback semantics.** When `canWrite` returns false (capability denied or connector offline), the tab stays read-only. If the user manages to type something via paste/drag (somehow), Save fails clearly rather than silently no-op.
- **Refresh after save.** The PATCH response includes a fresh signed URL (20-minute expiry per Harmoniq spec). We don't need to re-fetch the file content after save — local buffer is authoritative.
- **What about ⌘Z after save?** Local convention: undo stack persists. PM should be the same; the connector doesn't enforce a "no undoing past last save" rule.