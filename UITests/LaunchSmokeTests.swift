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
        let editor = app.descendants(matching: .any)["md-editor.main-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "main editor view not found by accessibility identifier")

        // Also confirm the Open… toolbar button is reachable by
        // identifier — exercises identifier-based discovery for an
        // interactive control, not just the text container.
        let openButton = app.descendants(matching: .any)["md-editor.toolbar.open-file"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5), "Open… button not found by accessibility identifier")
    }
}
