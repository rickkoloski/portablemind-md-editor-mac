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

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "app window did not appear")

        // Query by identifier. Do not rely on XCUITest's built-in
        // element-type classification for Cocoa-in-SwiftUI views.
        let editor = app.descendants(matching: .any)["md-editor.main-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "main editor view not found by accessibility identifier")
    }
}
