import XCTest

/// Minimum smoke test for D2: launches the app and confirms the main
/// editor view is accessible via its accessibilityIdentifier (NOT by
/// element-type query — that lesson is D1 finding #5 / engineering-
/// standards §2.1).
final class LaunchSmokeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndMainEditorIsAccessible() throws {
        let app = XCUIApplication()
        app.launch()

        // Query by identifier only, per engineering-standards §2.1.
        // Do not rely on XCUITest's built-in element-type classification
        // (`.windows`, `.textViews`, etc.) for SwiftUI-hosted Cocoa views
        // — per D1 finding #5 those queries are unreliable across the
        // SwiftUI AX wrapper.
        //
        // Post-D6, launch may land on the empty-editor placeholder
        // (no document open) instead of the main editor view. Either
        // is a valid "did the app launch?" signal. Tracked as i03 in
        // docs/issues_backlog.md; this test was failing pre-D18 because
        // it asserted on main-editor only.
        let mainEditor = app.descendants(matching: .any)["md-editor.main-editor"].firstMatch
        let emptyEditor = app.descendants(matching: .any)["md-editor.empty-editor"].firstMatch

        // Poll up to 10s for either to mount.
        let deadline = Date().addingTimeInterval(10)
        var mounted = false
        while Date() < deadline {
            if mainEditor.exists || emptyEditor.exists {
                mounted = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(mounted,
                      "neither main-editor nor empty-editor reached by identifier")

        // Also confirm the Open… toolbar button is reachable by
        // identifier — exercises identifier-based discovery for an
        // interactive control, not just the text container.
        let openButton = app.descendants(matching: .any)["md-editor.toolbar.open-file"].firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 5), "Open… button not found by accessibility identifier")
    }
}
