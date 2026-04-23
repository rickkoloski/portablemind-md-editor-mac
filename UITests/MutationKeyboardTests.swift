import XCTest

/// Exercises the keyboard-triggered mutation path end-to-end: the app
/// launches, the main editor is reachable by accessibilityIdentifier,
/// and typing + Cmd+A + Cmd+B produces a bold-wrapped source.
///
/// Per engineering-standards §2.1, queries are identifier-based only.
final class MutationKeyboardTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBoldMutationWrapsSelection() throws {
        let app = XCUIApplication()
        app.launch()

        let editor = app.descendants(matching: .any)["md-editor.main-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "main editor not reachable by identifier")

        // Focus the editor and type a word.
        editor.click()
        editor.typeText("hello")

        // Select All → Cmd+B.
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("b", modifierFlags: .command)

        // Read the buffer value via AX. With source intact, the raw
        // source should contain "**hello**" somewhere.
        let text = (editor.value as? String) ?? ""
        XCTAssertTrue(text.contains("**hello**"),
                      "expected source to contain **hello**; got: \(text)")
    }
}
