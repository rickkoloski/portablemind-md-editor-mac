// D30 phase 1 — SessionInterest invariants.
//
// Color is hash-derived from sessionID; same id → same color across
// runs (visual identity stability). Different ids → different colors
// (regression guard against everyone-gets-the-same-color bugs).

import AppKit
import XCTest
@testable import MdEditor

final class SessionInterestTests: XCTestCase {

    func testColorIsStableForSameSessionID() {
        let a = SessionInterest.deterministicColor(for: "cc1")
        let b = SessionInterest.deterministicColor(for: "cc1")
        XCTAssertEqual(componentsHex(of: a), componentsHex(of: b))
    }

    func testColorDiffersForDifferentSessionIDs() {
        let cc1 = SessionInterest.deterministicColor(for: "cc1")
        let cc2 = SessionInterest.deterministicColor(for: "cc2")
        let cc3 = SessionInterest.deterministicColor(for: "cc3")
        XCTAssertNotEqual(componentsHex(of: cc1), componentsHex(of: cc2))
        XCTAssertNotEqual(componentsHex(of: cc2), componentsHex(of: cc3))
        XCTAssertNotEqual(componentsHex(of: cc1), componentsHex(of: cc3))
    }

    func testColorIsStableForLongerSessionID() {
        let uuid = "A6199875-4C59-40B2-8DC4-678D8229AD45"
        let a = SessionInterest.deterministicColor(for: uuid)
        let b = SessionInterest.deterministicColor(for: uuid)
        XCTAssertEqual(componentsHex(of: a), componentsHex(of: b))
    }

    func testIDMatchesSessionID() {
        let interest = SessionInterest.make(sessionID: "cc7", label: "Sales review")
        XCTAssertEqual(interest.id, "cc7")
        XCTAssertEqual(interest.sessionID, "cc7")
        XCTAssertEqual(interest.label, "Sales review")
    }

    func testMakeSetsRegisteredAtToRecentTime() {
        let before = Date()
        let interest = SessionInterest.make(sessionID: "cc1")
        let after = Date()
        XCTAssertGreaterThanOrEqual(interest.registeredAt, before)
        XCTAssertLessThanOrEqual(interest.registeredAt, after)
    }

    func testLabelDefaultsNil() {
        let interest = SessionInterest.make(sessionID: "cc1")
        XCTAssertNil(interest.label)
    }

    private func componentsHex(of color: NSColor) -> String {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        return String(format: "%.4f-%.4f-%.4f-%.4f",
                      c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }
}
