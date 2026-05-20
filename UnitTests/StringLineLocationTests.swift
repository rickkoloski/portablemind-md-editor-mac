// D31 Phase 3 — round-trip + edge-case coverage for String line/index
// helpers. The forward direction (nsLocation(forLine:column:)) is
// existing (D9); the inverse (lineNumber(forCharacterIndex:)) is new
// and underpins scroll-position capture.

import XCTest
@testable import MdEditor

final class StringLineLocationTests: XCTestCase {

    // MARK: - lineNumber(forCharacterIndex:)

    func testEmptyStringYieldsLineOne() {
        XCTAssertEqual("".lineNumber(forCharacterIndex: 0), 1)
        XCTAssertEqual("".lineNumber(forCharacterIndex: 5), 1)
    }

    func testSingleLine() {
        let s = "hello"
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 0), 1)
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 4), 1)
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 100), 1, "out-of-range clamps to last line")
    }

    func testMultipleLines() {
        let s = "a\nb\nc"
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 0), 1)  // 'a'
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 1), 1)  // newline ending line 1
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 2), 2)  // 'b'
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 3), 2)  // newline ending line 2
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 4), 3)  // 'c'
    }

    func testNegativeClampsToOne() {
        XCTAssertEqual("a\nb".lineNumber(forCharacterIndex: -1), 1)
        XCTAssertEqual("a\nb".lineNumber(forCharacterIndex: -100), 1)
    }

    func testTrailingNewline() {
        let s = "a\nb\n"
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 4), 3,
                       "the position after the final newline is on a new (empty) line 3")
    }

    // MARK: - Round-trip with nsLocation(forLine:column:)

    func testRoundTripSeveralFixtures() {
        let fixtures: [String] = [
            "single line",
            "two\nlines",
            "three\nshort\nlines",
            "line\n\nempty middle\n",
            "trailing newline\n",
        ]
        for s in fixtures {
            let lineCount = s.components(separatedBy: "\n").count
            for line in 1...lineCount {
                let loc = s.nsLocation(forLine: line, column: 1)
                let back = s.lineNumber(forCharacterIndex: loc)
                XCTAssertEqual(back, line, "round-trip failed at line \(line) of \(s.debugDescription)")
            }
        }
    }

    func testMultibyteCharacters() {
        // Emoji counts as 2 UTF-16 code units; the NSString-based helper
        // works in UTF-16 units so the line break still lands correctly.
        let s = "🍕\nb"
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 0), 1)
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 2), 1, "second UTF-16 unit of emoji is still line 1")
        XCTAssertEqual(s.lineNumber(forCharacterIndex: 3), 2)
    }
}
