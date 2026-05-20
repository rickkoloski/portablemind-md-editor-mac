// D31 SC9 (partial) — XCUITest for the Open Recent menu.
//
// Spec: docs/current_work/specs/d31_mru_and_session_restore_spec.md §4
//
// Coverage strategy:
// - SC7 (first-launch empty state) → drafted here; currently skipped
//   due to i03 (SwiftUI Menu AX bridge unreliable). The launch-arg
//   reset infrastructure and the disabled-Button placeholder are still
//   useful — both help future harness-driven verification.
// - SC1, SC5, SC6 → covered by RecentItemsStoreTests (full state-
//   machine verification via UserDefaults round-trip) + the manual
//   test plan in Phase 6.

import XCTest

final class OpenRecentMenuTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// SC7 — fresh launch with wiped defaults shows the
    /// "(No Recent Files)" placeholder inside the Open Recent submenu.
    ///
    /// Currently skipped: SwiftUI Menu's NSMenu AX bridge does not
    /// expose submenu items with their accessibilityIdentifier
    /// reliably to XCUITest. Two query patterns tried 2026-05-15
    /// (`app.menuItems[...]` and `openRecentItem.menuItems[...]`),
    /// both fail to find the placeholder even though the submenu opens
    /// and the parent items resolve fine. Same root cause as i03 in
    /// docs/issues_backlog.md (XCUITest / SwiftUI-hosted AX wrapper).
    /// Re-enable when i03's harness-driven verification path lands.
    ///
    /// The placeholder being a disabled Button (rather than Text) is a
    /// UX + a11y improvement regardless — screen readers announce the
    /// empty state clearly.
    func testOpenRecentEmptyStatePlaceholder() throws {
        throw XCTSkip("i03: SwiftUI Menu AX-bridge identifier lookup unreliable; awaiting harness-driven verification per docs/issues_backlog.md")
    }
}
