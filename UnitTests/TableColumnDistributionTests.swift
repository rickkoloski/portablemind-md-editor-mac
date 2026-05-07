// D24.2 phase 2 — XCTest fixtures for TableColumnDistribution.distribute(...).
//
// New algorithm: three regimes (fits / slack / overflow) with Q8
// narrow-column threshold lock-in inside the slack regime.
//
// Spec: docs/current_work/specs/d24.2_slack_proportional_columns_spec.md
//
// Each test annotates its expected algorithm trace inline so failures
// can be debugged from the test file alone.

import XCTest
@testable import MdEditor

final class TableColumnDistributionTests: XCTestCase {

    private let eps: CGFloat = 0.001

    // MARK: - Helpers

    /// Builds `[ColumnContentMeasurement]` from `(min, max)` tuples.
    private func ms(_ pairs: (CGFloat, CGFloat)...) -> [ColumnContentMeasurement] {
        pairs.map { ColumnContentMeasurement(minContent: $0.0, maxContent: $0.1) }
    }

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

    // MARK: - Degenerate / fits regime

    func testEmptyInput_returnsEmpty() {
        let r = TableColumnDistribution.distribute(
            measurements: [],
            viewportWidth: 800)
        XCTAssertEqual(r, [])
    }

    func testSingleColumn_fitsRegime() {
        // Trace: sumMax=200 ≤ viewport=800 → fits regime → [200].
        let r = TableColumnDistribution.distribute(
            measurements: ms((100, 200)),
            viewportWidth: 800)
        XCTAssertEqual(r.count, 1)
        assertApprox(r[0], 200)
    }

    func testAllFits_fitsRegime() {
        // Trace: sumMax=450 ≤ viewport=800 → fits.
        let r = TableColumnDistribution.distribute(
            measurements: ms((100, 100), (150, 150), (200, 200)),
            viewportWidth: 800)
        XCTAssertEqual(r, [100, 150, 200])
    }

    func testAllFitsExactly_fitsRegime() {
        // Trace: sumMax=800 == viewport=800 → fits (uses ≤).
        let r = TableColumnDistribution.distribute(
            measurements: ms((200, 200), (300, 300), (300, 300)),
            viewportWidth: 800)
        XCTAssertEqual(r, [200, 300, 300])
    }

    // MARK: - Slack regime + Q8

    func testDecisionLogShape_q8LocksNarrowCols_slackFlexesWide() {
        // Trace: measurements = [Date(34.62, 86.54), Decision(70, 800), Decided(28, 28)]
        //   (Decision pre-capped at viewport=800 by caller before passing in.)
        //   sumMax=914.54 > viewport=800; sumMin=132.62 < 800 → slack regime.
        //   Q8 (threshold=120):
        //     Iter 1: pool=800.
        //       Date max=86.54<120, after-lock pool=713.46, remainingMin=70+28=98.
        //         713.46≥98 ✓.
        //       Decision max=800>120, skip.
        //       Decided max=28<120, after-lock pool=772, remainingMin=34.62+70=104.62.
        //         772≥104.62 ✓.
        //       Best by smallest max: Decided. Lock col 2. width=28.
        //     Iter 2: pool=772.
        //       Date max=86.54<120, after-lock pool=685.46, remainingMin=70.
        //         685.46≥70 ✓.
        //       Lock col 0. width=86.54.
        //     Iter 3: pool=685.46. Decision max>120. break.
        //   Slack on Decision: flex_pool=685.46, sum_flex_min=70, surplus=615.46,
        //     totalSlack=730. share=615.46. width(1)=70+615.46=685.46.
        //   Final: [86.54, 685.46, 28].
        let r = TableColumnDistribution.distribute(
            measurements: ms((34.62, 86.54), (70, 800), (28, 28)),
            viewportWidth: 800)
        assertApprox(r[0], 86.54, "Date locked at max")
        assertApprox(r[1], 685.46, "Decision flexes via slack")
        assertApprox(r[2], 28, "Decided by locked at max")
        assertApprox(r.reduce(0, +), 800)
    }

    func testNarrowDataColumnLocksAtMaxViaQ8() {
        // The actual regression case from Rick's report (viewport ≈ 250).
        // Trace: measurements = [Date(34.62, 86.54), Decision(70, 250), Decided(28, 28)]
        //   sumMax=364.54 > viewport=250; sumMin=132.62 < 250 → slack.
        //   Q8: Date locks (Iter 1: 86.54<120, after-lock pool=163.46, remMin=98 ✓);
        //       Decided locks (Iter 2: 28<120, similar). Decision skipped.
        //   Slack on Decision: flex_pool=135.46, sum_min=70, surplus=65.46,
        //     totalSlack=180, share=65.46. width=135.46.
        //   Final: [86.54, 135.46, 28]. Sum=250.
        let r = TableColumnDistribution.distribute(
            measurements: ms((34.62, 86.54), (70, 250), (28, 28)),
            viewportWidth: 250)
        assertApprox(r[0], 86.54, "Date stays at max even at narrow viewport — the regression fix")
        assertApprox(r[2], 28, "Decided also locked")
        // Decision flexes proportional to slack.
        assertApprox(r[1], 135.46)
        assertApprox(r.reduce(0, +), 250)
    }

    func testManyNarrowPlusOneWide_narrowsLockSequentially_wideFlexes() {
        // Trace: 5 narrow cols (50, 50) and 1 wide (50, 1000).
        //   viewport=1000. sumMax=250+1000=1250 > 1000.
        //   sumMin=300 < 1000 → slack.
        //   Q8: each narrow max=50<120; locks one per iter (ties: first by index).
        //     After 5 locks pool=750. Wide max=1000>120, skip. break.
        //   Slack on wide: flex_pool=750, sum_min=50, surplus=700, slack=950.
        //     share=700. width=750.
        //   Final: [50, 50, 50, 50, 50, 750]. Sum=1000.
        let r = TableColumnDistribution.distribute(
            measurements: ms((50, 50), (50, 50), (50, 50), (50, 50), (50, 50), (50, 1000)),
            viewportWidth: 1000)
        for i in 0..<5 { assertApprox(r[i], 50, "narrow col \(i) locked") }
        assertApprox(r[5], 750, "wide col flexes")
        assertApprox(r.reduce(0, +), 1000)
    }

    func testWideContentColumnFlexesViaSlack() {
        // Confirms Q8 doesn't over-trigger: cols above threshold flex.
        // Trace: measurements = [(70, 200), (70, 300)]. viewport=400.
        //   sumMax=500 > 400; sumMin=140 < 400 → slack.
        //   Q8: both max>120, no locks.
        //   flex_pool=400, sum_min=140, surplus=260.
        //   slack=[130, 230], totalSlack=360.
        //   shares: 130/360*260=93.888…, 230/360*260=166.111…
        //   widths: 70+93.89=163.89, 70+166.11=236.11.
        //   Final sum: 400.
        let r = TableColumnDistribution.distribute(
            measurements: ms((70, 200), (70, 300)),
            viewportWidth: 400)
        assertApprox(r[0], 70 + 130.0/360.0 * 260.0)
        assertApprox(r[1], 70 + 230.0/360.0 * 260.0)
        assertApprox(r.reduce(0, +), 400)
    }

    func testQ8ThresholdTunable() {
        // Same inputs, different thresholds → different outcomes.
        // measurements = [(50, 100), (50, 200)], viewport=200.
        // sumMax=300 > 200; sumMin=100 < 200 → slack.
        //
        // Threshold=120: col 0 max=100<120 locks. flex_pool=100, sum_min=50,
        //   surplus=50, slack=150, share=50. width(1)=100. Final [100, 100].
        let rDefault = TableColumnDistribution.distribute(
            measurements: ms((50, 100), (50, 200)),
            viewportWidth: 200,
            narrowThreshold: 120)
        XCTAssertEqual(rDefault.count, 2)
        assertApprox(rDefault[0], 100)
        assertApprox(rDefault[1], 100)

        // Threshold=80: col 0 max=100>80 doesn't lock. Both flex.
        //   flex_pool=200, sum_min=100, surplus=100.
        //   slack=[50, 150], totalSlack=200. shares: 25, 75. widths: 75, 125.
        let rTight = TableColumnDistribution.distribute(
            measurements: ms((50, 100), (50, 200)),
            viewportWidth: 200,
            narrowThreshold: 80)
        assertApprox(rTight[0], 75)
        assertApprox(rTight[1], 125)
    }

    func testQ8IteratesUntilFixpoint_constraintPreventsOverlocking() {
        // Trace: 4 narrow cols (50, 100). viewport=300, threshold=120.
        //   sumMax=400 > 300; sumMin=200 < 300 → slack.
        //   Q8 with "leaves room for remaining mins" constraint:
        //     Iter 1: pool=300. Col 0 candidate: after-lock pool=200,
        //       remMin=50*3=150. 200≥150 ✓. Lock col 0.
        //     Iter 2: pool=200. Col 1: after-lock pool=100, remMin=100.
        //       100≥100 ✓. Lock col 1.
        //     Iter 3: pool=100. Col 2: after-lock pool=0, remMin=50.
        //       0<50 ✗. Col 3 same. No candidates. break.
        //   Slack on cols 2,3: flex_pool=100, sum_min=100, surplus=0,
        //     totalSlack=100 (each has slack=50). shares: 50/100*0=0 each.
        //     widths pre-floor: 50, 50.
        //   Floor clamp: each col effective floor = min(maxContent=100, 60) = 60.
        //     widths post-floor: 60, 60.
        //   Final: [100, 100, 60, 60]. Sum=320 > viewport=300.
        //   This is expected per spec Q3: floor wins over fitting in this
        //   sub-case (a flex col's natural slack share landed below floor).
        let r = TableColumnDistribution.distribute(
            measurements: ms((50, 100), (50, 100), (50, 100), (50, 100)),
            viewportWidth: 300)
        assertApprox(r[0], 100)
        assertApprox(r[1], 100)
        assertApprox(r[2], 60)
        assertApprox(r[3], 60)
        // Sum slightly exceeds viewport because of the floor clamp on
        // unlocked flex cols 2 and 3.
        assertApprox(r.reduce(0, +), 320)
    }

    func testAllFlex_proportionalDistribution() {
        // No col below threshold; pure slack distribution.
        // Trace: measurements = [(100, 400), (100, 500), (100, 600)]
        //   viewport=600. sumMax=1500 > 600. sumMin=300 < 600 → slack.
        //   Q8: all max > 120, no locks.
        //   flex_pool=600, sum_min=300, surplus=300.
        //   slack=[300, 400, 500], totalSlack=1200.
        //   shares: 300/1200*300=75, 400/1200*300=100, 500/1200*300=125.
        //   widths: 175, 200, 225. Sum=600.
        let r = TableColumnDistribution.distribute(
            measurements: ms((100, 400), (100, 500), (100, 600)),
            viewportWidth: 600)
        assertApprox(r[0], 175)
        assertApprox(r[1], 200)
        assertApprox(r[2], 225)
        assertApprox(r.reduce(0, +), 600)
    }

    func testAllNarrow_fitsRegime() {
        // Trace: sumMax=225 ≤ viewport=600 → fits → return maxes.
        let r = TableColumnDistribution.distribute(
            measurements: ms((50, 50), (75, 75), (100, 100)),
            viewportWidth: 600)
        XCTAssertEqual(r, [50, 75, 100])
    }

    func testOneSuperLong_othersLockViaQ8() {
        // Caller pre-capped the long col's max at viewport.
        // measurements = [(60, 60), (60, 60), (60, 800)], viewport=800.
        //   sumMax=920 > 800. sumMin=180 < 800 → slack.
        //   Q8: cols 0, 1 max=60<120. Locks them. Col 2 max=800>120, skip.
        //   Slack on col 2: flex_pool=680, sum_min=60, surplus=620, slack=740.
        //     share=620. width(2)=60+620=680.
        //   Final: [60, 60, 680]. Sum=800.
        let r = TableColumnDistribution.distribute(
            measurements: ms((60, 60), (60, 60), (60, 800)),
            viewportWidth: 800)
        assertApprox(r[0], 60)
        assertApprox(r[1], 60)
        assertApprox(r[2], 680)
        assertApprox(r.reduce(0, +), 800)
    }

    // MARK: - Overflow regime

    func testOverflowRegime_returnsMins() {
        // sumMin > viewport: overflow regime.
        // measurements = [(200, 200), (200, 200), (200, 200)], viewport=100.
        //   sumMin=600 ≥ 100. Return mins. Floor: min(200,60)=60. max(200,60)=200.
        //   Final: [200, 200, 200]. Sum=600 > viewport.
        let r = TableColumnDistribution.distribute(
            measurements: ms((200, 200), (200, 200), (200, 200)),
            viewportWidth: 100,
            minWidthFloor: 60)
        XCTAssertEqual(r, [200, 200, 200])
        XCTAssertGreaterThan(r.reduce(0, +), 100,
            "overflow regime: sum may exceed viewport per spec Q2")
    }

    // MARK: - Floor wins (post-pass clamp)

    func testFloorWins_overflowRegimeWithSmallMins() {
        // measurements = [(40, 100), (40, 100)], viewport=80.
        //   sumMin=80 ≥ viewport=80 → overflow regime.
        //   mins = [40, 40]. Floor: effective floor = min(100,60)=60.
        //   Clamp: max(40,60)=60. Final [60, 60]. Sum=120 > viewport=80.
        let r = TableColumnDistribution.distribute(
            measurements: ms((40, 100), (40, 100)),
            viewportWidth: 80,
            minWidthFloor: 60)
        assertApprox(r[0], 60)
        assertApprox(r[1], 60)
        XCTAssertGreaterThan(r.reduce(0, +), 80,
            "floor-wins case: sum exceeds viewport per spec Q3")
    }

    func testFloorWins_colWithMaxBelowFloorStaysAtMax() {
        // Col whose maxContent < minWidthFloor doesn't get blown up
        // to the floor — effective floor = min(max, floor) = max.
        // measurements = [(15, 30), (15, 30), (200, 200)], viewport=80.
        //   sumMin=230 ≥ 80 → overflow regime.
        //   mins=[15, 15, 200]. Floors: min(30,60)=30, min(30,60)=30,
        //     min(200,60)=60. Clamp: max(15,30)=30, max(15,30)=30,
        //     max(200,60)=200. Final [30, 30, 200].
        let r = TableColumnDistribution.distribute(
            measurements: ms((15, 30), (15, 30), (200, 200)),
            viewportWidth: 80,
            minWidthFloor: 60)
        assertApprox(r[0], 30, "max=30<floor → stays at maxContent")
        assertApprox(r[1], 30)
        assertApprox(r[2], 200, "wide col stays at min above floor")
    }

    // MARK: - Determinism + sweep invariants

    func testDeterminism_sameInputsSameOutputs() {
        let inputs = ms((34.62, 86.54), (70, 800), (28, 28),
                        (50, 100), (200, 1500))
        let r1 = TableColumnDistribution.distribute(measurements: inputs, viewportWidth: 1000)
        let r2 = TableColumnDistribution.distribute(measurements: inputs, viewportWidth: 1000)
        let r3 = TableColumnDistribution.distribute(measurements: inputs, viewportWidth: 1000)
        XCTAssertEqual(r1, r2)
        XCTAssertEqual(r2, r3)
    }

    func testSumInvariant_acrossViewportSweep() {
        // Sweep viewports for a Decision-log-shape fixture. Asserts per-
        // column sanity (no NaN/Inf/negative; each col >= effective floor;
        // each col <= maxContent), per-regime sum bounds (with allowance
        // for floor-clamp overshoot in the slack regime per spec Q3), and
        // an absolute upper bound on the total (sum can't exceed sumMax).
        let measurements = ms((34.62, 86.54), (70, 800), (28, 28))
        let sumMin = measurements.reduce(CGFloat(0)) { $0 + $1.minContent }
        let sumMax = measurements.reduce(CGFloat(0)) { $0 + $1.maxContent }
        let floor: CGFloat = 60
        for vw: CGFloat in stride(from: 50, through: 2000, by: 25) {
            let r = TableColumnDistribution.distribute(
                measurements: measurements, viewportWidth: vw)
            XCTAssertEqual(r.count, measurements.count, "vw=\(vw)")
            for (i, w) in r.enumerated() {
                XCTAssertFalse(w.isNaN, "NaN at vw=\(vw) col=\(i)")
                XCTAssertFalse(w.isInfinite, "Inf at vw=\(vw) col=\(i)")
                XCTAssertGreaterThanOrEqual(w, 0, "negative at vw=\(vw) col=\(i)")
                let effFloor = min(measurements[i].maxContent, floor)
                XCTAssertGreaterThanOrEqual(
                    w, effFloor - eps,
                    "below floor at vw=\(vw) col=\(i): w=\(w) floor=\(effFloor)")
                XCTAssertLessThanOrEqual(
                    w, measurements[i].maxContent + eps,
                    "exceeds maxContent at vw=\(vw) col=\(i): w=\(w) max=\(measurements[i].maxContent)")
            }
            let total = r.reduce(0, +)
            if sumMax <= vw {
                // Fits regime
                assertApprox(total, sumMax, "fits sum invariant at vw=\(vw)")
            } else if sumMin >= vw {
                // Overflow regime: sum is at least sumMin (mins are returned;
                // floor only ever pulls UP).
                XCTAssertGreaterThanOrEqual(
                    total, sumMin - eps,
                    "overflow sum invariant at vw=\(vw)")
            } else {
                // Slack regime: sum normally == viewport. Floor clamp on a
                // flex col with slack-share < effective floor can push the
                // sum above viewport per spec Q3 ("floor wins over fitting").
                // Bounded above by sumMax (no col exceeds its max).
                XCTAssertLessThanOrEqual(
                    total, sumMax + eps,
                    "slack regime upper bound at vw=\(vw)")
            }
        }
    }

    // MARK: - Degenerate inputs (no crash)

    func testZeroViewport_returnsMinsClampedToFloor() {
        // viewport=0: sumMin >= 0, overflow regime.
        // mins=[50, 100, 200]. Floors: 50→50 (max=50<60→eff floor=50),
        //   100→60, 200→60. Clamp: [50, 100, 200].
        let r = TableColumnDistribution.distribute(
            measurements: ms((50, 50), (100, 100), (200, 200)),
            viewportWidth: 0)
        assertApprox(r[0], 50)
        assertApprox(r[1], 100)
        assertApprox(r[2], 200)
    }

    func testZeroNaturalsButViewportPositive_fitsRegime() {
        // sumMax=0 ≤ viewport → fits → return maxes (all zero).
        let r = TableColumnDistribution.distribute(
            measurements: ms((0, 0), (0, 0), (0, 0)),
            viewportWidth: 600)
        XCTAssertEqual(r, [0, 0, 0])
    }
}
