import XCTest

/// The one automated check for the D1 spike: proves (or proves we cannot
/// prove) that TextKit 2's accessibility tree exposes enough for
/// XCUITest to verify the cursor-on-line delimiter reveal.
///
/// If the test can't be written cleanly, that outcome is itself a
/// finding — it tells us later UI-test strategy can't rely on the AX
/// tree alone.
final class CursorOnLineLitmusTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndTextViewExists() throws {
        let app = XCUIApplication()
        app.launch()

        // At minimum: the window and a text view exist.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
    }

    // Intentional: the litmus test itself is a TODO until we learn
    // whether the AX tree exposes per-range attributes. The findings doc
    // will record the outcome — passed, failed meaningfully, or
    // unwriteable — per the plan's Step 8.
}
