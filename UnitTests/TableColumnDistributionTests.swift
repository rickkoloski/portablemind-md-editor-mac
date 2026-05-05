// D24 phase 3 — XCTest fixtures for TableColumnDistribution.distribute(...).
//
// Spec edge cases (plan §Phase 3 DOD):
//   - All fits naturally (sum ≤ viewport)
//   - Some lock, others flex
//   - All flex (no narrow columns)
//   - One super-long, rest narrow (decision-log shape)
//   - All narrow (every column locks)
//   - Single column
//   - Empty
//   - Floor wins (viewport < minWidthFloor × n)
//
// Plus invariants:
//   - Determinism (same inputs → same outputs).
//   - Sum-of-widths ≤ viewportWidth unless floor-wins branch fires.

import XCTest
@testable import MdEditor

final class TableColumnDistributionTests: XCTestCase {

    private let eps: CGFloat = 0.001

    // MARK: - Helpers

    /// Asserts `actual` ≈ `expected` within `eps`, with descriptive failure.
    private func assertApprox(
        _ actual: CGFloat,
        _ expected: CGFloat,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            Double(actual), Double(expected),
            accuracy: Double(eps),
            message,
            file: file, line: line)
    }

    // MARK: - Fits-naturally

    func testEmptyInput_returnsEmpty() {
        let result = TableColumnDistribution.distribute(
            naturalWidths: [],
            viewportWidth: 800)
        XCTAssertEqual(result, [])
    }

    func testSingleColumn_locksAtNatural() {
        let r = TableColumnDistribution.distribute(
            naturalWidths: [200],
            viewportWidth: 800)
        XCTAssertEqual(r.count, 1)
        assertApprox(r[0], 200)
    }

    func testAllFits_locksEveryColumnAtNaturalWidth() {
        let naturals: [CGFloat] = [100, 150, 200]   // sum = 450
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: 800)
        XCTAssertEqual(r, naturals)
    }

    func testAllFitsExactly_locksEveryColumn() {
        // Sum exactly equals viewport — boundary of the "fits" branch.
        let naturals: [CGFloat] = [200, 300, 300]   // sum = 800
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: 800)
        XCTAssertEqual(r, naturals)
    }

    // MARK: - Lock-in + flex

    func testDecisionLogShape_shortColsLock_longColFlexes() {
        // Date | Decision | Decided by — the canonical i02 case.
        let naturals: [CGFloat] = [86, 1090, 86]   // sum = 1262
        let viewport: CGFloat = 800
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: viewport)

        XCTAssertEqual(r.count, 3)
        // Date and Decided by should lock at their natural widths
        // (both << equal_share of 800/3).
        assertApprox(r[0], 86, "Date column should lock at natural width")
        assertApprox(r[2], 86, "Decided by column should lock at natural width")
        // Decision column gets the rest.
        assertApprox(r[1], viewport - 86 - 86, "Decision column should fill remainder")
        // Sum should equal viewport.
        assertApprox(r.reduce(0, +), viewport)
    }

    func testManyNarrowPlusOneWide_narrowAllLock_wideTakesRest() {
        // Five narrow + one wide.
        let naturals: [CGFloat] = [50, 50, 50, 50, 50, 1500]   // sum = 1750
        let viewport: CGFloat = 1000
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: viewport)
        // Narrow cols all lock at 50pt. Wide takes 1000 - 250 = 750.
        for i in 0..<5 { assertApprox(r[i], 50) }
        assertApprox(r[5], 750)
        assertApprox(r.reduce(0, +), viewport)
    }

    // MARK: - All flex

    func testAllFlex_proportionalDistribution() {
        // No column small enough to lock at the equal-share threshold.
        // viewport=600, equalShare=200. naturals all > 200.
        let naturals: [CGFloat] = [400, 500, 600]   // sum = 1500
        let viewport: CGFloat = 600
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: viewport)
        // Proportional shares: 400/1500*600 = 160, 500/1500*600 = 200,
        // 600/1500*600 = 240. None below 60pt floor → no clamp.
        // But: 160 < min(400, 60) = 60? No, 160 > 60 so ok.
        assertApprox(r[0], 160)
        assertApprox(r[1], 200)
        assertApprox(r[2], 240)
        assertApprox(r.reduce(0, +), viewport)
    }

    // MARK: - All narrow

    func testAllNarrow_everyColumnLocks() {
        // viewport=600, n=3, equalShare=200. All naturals < 200.
        let naturals: [CGFloat] = [50, 75, 100]
        let viewport: CGFloat = 600
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: viewport)
        // total natural = 225 ≤ 600 → "fits naturally" branch.
        XCTAssertEqual(r, naturals)
    }

    // MARK: - One super-long with rest narrow

    func testOneSuperLong_othersLock_longFlexes() {
        // The "natural pre-capped at viewport" Q8 case: caller has
        // already capped the long column at viewportWidth.
        let naturals: [CGFloat] = [60, 60, 800]   // long col == viewport
        let viewport: CGFloat = 800
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: viewport)
        // Two narrow lock at 60pt. Long col gets 800 - 120 = 680.
        assertApprox(r[0], 60)
        assertApprox(r[1], 60)
        assertApprox(r[2], 680)
        assertApprox(r.reduce(0, +), viewport)
    }

    // MARK: - Floor wins

    func testFloorWins_viewportSmallerThanFloorTimesN() {
        // viewport = 100, n = 3, floor = 60 → floor*n = 180 > viewport.
        // Every col would proportionally get below 60, so the floor
        // raises them. Spec: floor wins, accept overflow.
        let naturals: [CGFloat] = [200, 200, 200]   // sum = 600 >> 100
        let viewport: CGFloat = 100
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: viewport,
            minWidthFloor: 60)
        // All three columns should be exactly at floor (60pt). Sum=180 > viewport.
        for w in r { assertApprox(w, 60) }
        assertApprox(r.reduce(0, +), 180)
        XCTAssertGreaterThan(r.reduce(0, +), viewport,
            "Sum-of-widths invariant: floor-wins branch allows overflow")
    }

    func testFloorWins_someColsAlreadyBelowFloorNaturally() {
        // Some columns have natural < floor. min_width(col) = natural,
        // so those don't get raised. The floor only raises cols with
        // natural >= floor.
        let naturals: [CGFloat] = [30, 30, 200]   // sum = 260
        let viewport: CGFloat = 50  // < floor*n
        let r = TableColumnDistribution.distribute(
            naturalWidths: naturals,
            viewportWidth: viewport,
            minWidthFloor: 60)
        // First two cols: natural < floor → min_width = 30, lock at 30.
        // (Total natural > viewport so we enter else branch.)
        // After lock-in: cols 0+1 lock at 30 each (each ≤ equal_share = 50/3 ≈ 16.7? no 30 > 16.7 so they don't lock first round).
        // Actually let me compute: equal_share initially = 50/3 ≈ 16.67. None of (30,30,200) ≤ 16.67. So no lock-in.
        // Flex distribution: 30/260 * 50 ≈ 5.77 → max(30, 5.77) = 30. 30/260*50 ≈ 5.77 → 30. 200/260*50 ≈ 38.5 → max(60, 38.5) = 60.
        // Sum = 30 + 30 + 60 = 120 > viewport=50. Floor-wins reduction:
        //   excess = 70. above-floor cols = col 2 with headroom 60-60=0 → reducible=0.
        //   First two cols are at floor 30 (their min_width). Col 2 is at floor 60. Nothing to reduce.
        //   Accept overflow: result = [30, 30, 60].
        assertApprox(r[0], 30)
        assertApprox(r[1], 30)
        assertApprox(r[2], 60)
    }

    // MARK: - Determinism

    func testDeterminism_sameInputsSameOutputs() {
        let naturals: [CGFloat] = [86, 1090, 86, 200, 1500]
        let viewport: CGFloat = 1000
        let r1 = TableColumnDistribution.distribute(
            naturalWidths: naturals, viewportWidth: viewport)
        let r2 = TableColumnDistribution.distribute(
            naturalWidths: naturals, viewportWidth: viewport)
        let r3 = TableColumnDistribution.distribute(
            naturalWidths: naturals, viewportWidth: viewport)
        XCTAssertEqual(r1, r2)
        XCTAssertEqual(r2, r3)
    }

    // MARK: - Sum-of-widths invariant

    func testSumInvariant_acrossViewportSweep() {
        // Sweep viewport widths against a complex column shape; assert
        // sum-of-widths == viewport exactly when the algorithm consumes
        // the viewport (the normal case), or > viewport only in the
        // floor-wins regime.
        let naturals: [CGFloat] = [80, 60, 800, 200, 50]   // sum = 1190
        for vw: CGFloat in stride(from: 100, through: 2000, by: 50) {
            let r = TableColumnDistribution.distribute(
                naturalWidths: naturals, viewportWidth: vw)
            let total = r.reduce(0, +)
            // No NaN / negative widths.
            for w in r {
                XCTAssertGreaterThan(w, 0, "negative or zero width at vw=\(vw)")
                XCTAssertFalse(w.isNaN, "NaN width at vw=\(vw)")
                XCTAssertFalse(w.isInfinite, "Infinite width at vw=\(vw)")
            }
            // Floor: each col at least min(natural, 60).
            for (i, w) in r.enumerated() {
                let floor = Swift.min(naturals[i], 60)
                XCTAssertGreaterThanOrEqual(
                    w, floor - eps,
                    "col \(i) below floor \(floor) at vw=\(vw)")
            }
            // Sum constraint:
            //   - If naturals fit: sum == sum(naturals).
            //   - Else: sum ≤ vw, OR floor-wins overflow.
            let totalNatural = naturals.reduce(0, +)
            if totalNatural <= vw {
                assertApprox(total, totalNatural,
                    "fits-naturally branch should keep sum = sum(naturals) at vw=\(vw)")
            } else {
                let floorTotal = naturals.reduce(CGFloat(0)) { $0 + Swift.min($1, 60) }
                let isFloorWins = vw < floorTotal
                if isFloorWins {
                    XCTAssertGreaterThanOrEqual(total, vw - eps)
                } else {
                    XCTAssertLessThanOrEqual(total, vw + eps,
                        "non-floor-wins regime should sum ≤ viewport at vw=\(vw)")
                }
            }
        }
    }

    // MARK: - No-crash inputs

    func testZeroViewport_returnsFloor() {
        let r = TableColumnDistribution.distribute(
            naturalWidths: [50, 100, 200],
            viewportWidth: 0)
        // Degenerate viewport: each col returns min(natural, floor).
        assertApprox(r[0], 50)
        assertApprox(r[1], 60)
        assertApprox(r[2], 60)
    }

    func testZeroNaturalsButViewportPositive_returnsZeros() {
        // Edge: every column has zero natural width. Sum=0 ≤ viewport →
        // "fits naturally" branch returns naturals unchanged.
        let r = TableColumnDistribution.distribute(
            naturalWidths: [0, 0, 0],
            viewportWidth: 600)
        XCTAssertEqual(r, [0, 0, 0])
    }
}
