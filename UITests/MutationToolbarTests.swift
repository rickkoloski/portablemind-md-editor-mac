import XCTest

/// Exercises the toolbar-triggered mutation path: launch the app,
/// type, select, click the Bold toolbar button by identifier, assert
/// source is wrapped. Per engineering-standards §2.1 the query is
/// identifier-based; per §2.3 no chord checks live in the test.
final class MutationToolbarTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBoldButtonWrapsSelection() throws {
        let app = XCUIApplication()
        app.launch()

        let editor = app.descendants(matching: .any)["md-editor.main-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "main editor not reachable by identifier")

        editor.click()
        editor.typeText("hi")
        editor.typeKey("a", modifierFlags: .command)

        // `descendants(matching:.any)["id"]` returns a query; SwiftUI's
        // Button-wrapping-Label nesting means two AX elements share the
        // same identifier (outer button cell + inner content). Resolve
        // with .firstMatch so we click a single element rather than
        // fail on ambiguity. Still identifier-based per §2.1 — the
        // discipline is about NOT using element-type shortcuts like
        // `app.buttons[...]`, which continue to be unreliable for
        // SwiftUI-hosted views.
        let boldButton = app.descendants(matching: .any)["md-editor.toolbar.bold"].firstMatch
        XCTAssertTrue(boldButton.waitForExistence(timeout: 5), "Bold toolbar button not found by identifier")
        boldButton.click()

        let text = (editor.value as? String) ?? ""
        XCTAssertTrue(text.contains("**hi**"),
                      "expected source to contain **hi** after Bold click; got: \(text)")
    }
}
