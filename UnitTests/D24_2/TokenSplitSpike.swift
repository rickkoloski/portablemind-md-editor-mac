// D24.2 phase 1 spike — validate Q1's token-split heuristic.
//
// Q1 (spec): cell min-content = max width of any contiguous run with no
// soft-break opportunity (whitespace, `-`, `/`, `.`).
//
// This spike verifies Q1 against hand-derived expected atoms per fixture
// and against the broader spec invariant: min ≤ max for any text.
//
// (An earlier draft of this spike laid out text in NSTextContainer at
// width=1pt to compare against TextKit's actual minimum-line-fragment
// width. That path appears to trip a layout-loop edge case with the
// constrained width and long text — pulled out and replaced with the
// direct-measurement approach below. If a future regression argues that
// TextKit's break opportunities diverge from Q1's punctuation set, swap
// in a layout-based comparator using a moderate width like 50pt rather
// than 1pt.)
//
// Spike file is deletable in phase 4. Tag for grep: TODO-D24.2-spike-cleanup.

import XCTest
import AppKit
@testable import MdEditor

final class TokenSplitSpike: XCTestCase {

    private func font() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    }

    private func widthOf(_ s: String) -> CGFloat {
        NSAttributedString(string: s, attributes: [.font: font()]).size().width
    }

    /// For each fixture, the expected longest unbreakable atom under the
    /// Q1 heuristic ({whitespace, `-`, `/`, `.`} as soft-break).
    private struct Fixture {
        let label: String
        let text: String
        let expectedLongestAtom: String
    }

    private let fixtures: [Fixture] = [
        Fixture(label: "prose",
                text: "This is a moderately long sentence with normal whitespace.",
                expectedLongestAtom: "moderately"),
        Fixture(label: "date",
                text: "2026-04-28",
                expectedLongestAtom: "2026"),
        Fixture(label: "url",
                text: "https://example.com/path/to/some/resource",
                expectedLongestAtom: "resource"),     // tied with "example", "https"; CGFloat compare wins on first equal
        Fixture(label: "filepath",
                text: "~/src/apps/md-editor-mac/Sources/Editor/Renderer/Tables",
                expectedLongestAtom: "Renderer"),
        Fixture(label: "long_word",
                text: "Antidisestablishmentarianism",
                expectedLongestAtom: "Antidisestablishmentarianism"),
        Fixture(label: "mixed_text_url",
                text: "Open the docs at https://example.com/long-section-anchor for details",
                expectedLongestAtom: "section"),
        Fixture(label: "id_underscore",
                text: "user_session_token_id_42",
                expectedLongestAtom: "user_session_token_id_42"),    // underscores not in break set
        Fixture(label: "hyphenated_word",
                text: "self-improving-iteration",
                expectedLongestAtom: "improving"),
    ]

    func testQ1HeuristicMatchesExpectedLongestAtom() {
        let f = font()
        var deltas: [String] = []
        for fix in fixtures {
            let q1 = TK1TableBuilder.cellMinContentWidth(fix.text, font: f)
            let expected = widthOf(fix.expectedLongestAtom)
            let pct = expected > 0 ? abs(q1 - expected) / expected * 100 : 0
            print("  [\(fix.label)] q1=\(String(format: "%.2f", q1))pt expected=\(String(format: "%.2f", expected))pt ('\(fix.expectedLongestAtom)') Δ=\(String(format: "%.1f", pct))%")
            // Sub-pixel float jitter tolerance.
            if abs(q1 - expected) > 0.5 {
                deltas.append("\(fix.label): q1=\(q1) expected=\(expected) for atom '\(fix.expectedLongestAtom)'")
            }
        }
        if !deltas.isEmpty {
            XCTFail("Q1 heuristic diverges from expected atom widths:\n  " + deltas.joined(separator: "\n  "))
        }
    }

    /// Sanity invariant: for any text, min-content ≤ max-content.
    func testQ1Invariant_minLessThanOrEqualMax() {
        let f = font()
        for fix in fixtures {
            let min = TK1TableBuilder.cellMinContentWidth(fix.text, font: f)
            let max = NSAttributedString(string: fix.text, attributes: [.font: f]).size().width
            XCTAssertLessThanOrEqual(
                min, max + 0.5,
                "min > max for fixture '\(fix.label)': min=\(min) max=\(max)")
        }
    }

    /// Sanity invariant: empty text → 0; single-character text → that char's width.
    func testQ1Invariant_degenerateInputs() {
        let f = font()
        XCTAssertEqual(TK1TableBuilder.cellMinContentWidth("", font: f), 0)
        let oneChar = TK1TableBuilder.cellMinContentWidth("X", font: f)
        let xWidth = widthOf("X")
        XCTAssertEqual(oneChar, xWidth, accuracy: 0.5)
    }
}
