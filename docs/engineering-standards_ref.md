# Engineering Standards & Cross-Deliverable Considerations

**Type:** Reference (per `~/src/ops/sdlc/operations/conventions.md` — standards/guardrails that apply across the project lifetime).
**Status:** Active — additive over time; never retroactively weaken a committed standard without explicit CD approval recorded below.

## Why this file exists

The SDLC keeps individual deliverables (D1, D2, ...) bounded and self-contained. But some decisions — particularly ones that make future work easier or harder — need to persist *across* deliverables and survive Claude Code session turnover / context compaction.

This file is the durable record of those decisions. Every deliverable spec should:
1. Trace any relevant standard from here in its design section.
2. Flag in its "Out of Scope" section anything that *defers* a standard, with the reason and the deliverable where it will be picked up.
3. Never silently violate a standard.

When a new cross-deliverable consideration emerges, add it here and reference it from the relevant deliverable's completion record.

## How to read an entry

Each entry is a **rule** plus the **reason** it exists, the **consequences of not honoring it**, and (where useful) the **deliverable where the need first surfaced**. The reason-and-consequence framing is deliberate — future-you should be able to judge edge cases instead of blindly following the rule.

---

## Section 1 — Deployment readiness

Decisions that keep direct-download distribution (Developer ID + notarization + Sparkle DMG) mechanical rather than a rewrite, even though v1 ships outside the Mac App Store.

### 1.1 Sandbox-safe source code from day one
- **Rule:** All source code must be compatible with the macOS App Sandbox, even before we enable the sandbox entitlement.
- **In practice:**
  - User file access only via `NSOpenPanel` / `NSSavePanel` or drag-drop. Then retain access across launches via security-scoped bookmarks.
  - Never hardcode `/tmp`, `~/Desktop`, `~/Documents`, or other absolute paths; use the user-selected location.
  - Never write outside the user-granted scope, app's container, or `UserDefaults`.
  - Do not call any private API or use any non-sandbox-allowable entitlement.
- **Reason:** Vision Principle 2 + `docs/portablemind-positioning.md` commits us to an eventual Mac App Store distribution as the upsell path to PortableMind-connected mode. The App Store requires sandbox. A codebase written without sandbox discipline needs a painful retrofit pass; a sandbox-safe codebase enables sandbox later with one entitlement flip.
- **Consequence of violation:** Weeks of rework when we flip the entitlement; file-access bugs that only manifest in the sandboxed build.
- **Surfaced in:** D1 → D2 transition (noted during stack-alternatives Axis 5 and the B-vs-A decision for D2).

### 1.2 Lock in the canonical bundle identifier now, never change it
- **Rule:** The app's `PRODUCT_BUNDLE_IDENTIFIER` is **`ai.portablemind.md-editor`**. Spike variants may add a `.spike.dNN` suffix; the real app uses the canonical ID.
- **In practice:** Configure it in the project settings at first creation; don't change it even for cosmetic reasons.
- **Reason:** Developer ID certificates, provisioning profiles, Sparkle appcast, notarization records, and Mac App Store listings all bind to the bundle identifier. Any rename after certificates exist invalidates them and costs a fresh setup pass.
- **Consequence of violation:** Wasted cert enrollment time, confused appcasts, user-visible "app moved" dialogs, broken auto-update.
- **Surfaced in:** D1 → D2 transition.

### 1.3 Info.plist completeness from project creation
- **Rule:** The app's Info.plist must carry the full set of production-required keys from the first commit, even before the app ships anywhere.
- **In practice — required keys at project creation:**
  - `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier`, `CFBundleVersion`, `CFBundleShortVersionString`
  - `LSMinimumSystemVersion` — matches our declared minimum macOS
  - `LSApplicationCategoryType` — `public.app-category.productivity` (or more specific, chosen once)
  - `NSHumanReadableCopyright` — "© 2026 PortableMind" or agreed equivalent
  - `NSPrincipalClass` — `NSApplication`
  - `LSUIElement` — `NO` (we're a foreground, dock-visible app)
  - `NSSupportsAutomaticTermination` / `NSSupportsSuddenTermination` — set explicitly
  - `SUFeedURL` / `SUPublicEDKey` — reserved keys for Sparkle; add when Sparkle lands, but leave a TODO in place.
- **Reason:** Notarization, the App Store, and several macOS-integration features (Services menu, Spotlight, Open-With) read these keys. Missing or wrong values produce opaque rejection messages at notarization time or weird runtime behavior that's hard to diagnose.
- **Consequence of violation:** Notarization rejections, Gatekeeper warnings users can't bypass, wrong Dock tile, blank "About" panels.
- **Surfaced in:** D1 → D2 transition.

### 1.4 Apple Developer Program enrollment — gating item, not a standard
- **Status:** Open item, not a rule. Records a known gating dependency.
- **Who owns:** Rick (CD).
- **Need:** Developer ID signing and notarization require an active Apple Developer Program membership ($99/year). First-time enrollment runs 24–48 hours of identity verification. Notarization additionally requires an app-specific Apple ID password generated under that developer account.
- **Deliverable where this becomes blocking:** D3 (deployment packaging), or any earlier deliverable that wants to hand the app to a second machine.
- **Action if not yet enrolled:** kick off enrollment in parallel with the deliverable preceding packaging work, so the 24–48 hour verification doesn't stall us.

---

## Section 2 — Test & accessibility discipline

### 2.1 accessibilityIdentifier on every interactive NSView
- **Rule:** Every `NSView` (or AppKit control) that a user or test might interact with has an `accessibilityIdentifier` set at construction, derived from a shared constants file.
- **Reason:** D1 finding #5 — `XCUIApplication.textViews` and similar element-type queries do not reliably classify Cocoa-in-SwiftUI views. Identifier-based queries are always reliable, and Apple documents this as the recommended approach.
- **Consequence of violation:** UI tests silently pass on element-not-found, OR fail cryptically once a view moves across refactors.
- **Surfaced in:** D1 (XCUITest finding).

### 2.2 Never access `NSTextView.layoutManager` — TextKit 2 only
- **Rule:** Code that touches `NSTextView` uses `textLayoutManager` exclusively. The property `layoutManager` is never referenced, not even in diagnostics, not even in comments-with-real-code.
- **Reason:** D1 finding #1 — accessing `.layoutManager` lazy-creates a TextKit 1 layout manager and silently flips the view's code path. Our entire text-rendering architecture depends on being in the TextKit 2 path.
- **Consequence of violation:** Silent fallback to TextKit 1 with mysterious rendering regressions; attribute-based collapse behavior stops working.
- **Enforcement (future):** add a SwiftLint rule or pre-commit grep to fail on any occurrence of `.layoutManager` outside this standards doc.
- **Surfaced in:** D1.

---

## Section 3 — (Reserved for future standards)

Additional sections to be added when the needs surface. Candidates likely to emerge:
- Localization / string-tables discipline (Principle 2 requires shared SDLC artifacts produce per-OS string tables).
- Test evidence-capture standards (per `~/src/ops/sdlc/lifecycles/native.md` §Testing).
- Logging and diagnostic conventions.
- Code review and merge discipline (once we're >1 human contributor).

Add sections by number; keep each section self-contained with the rule + reason + consequence structure above.

---

## Change log

- **2026-04-22** — Initial creation. Section 1 (Deployment readiness) populated from the D1 → D2 transition conversation. Section 2 populated from D1 findings #1 and #5.
