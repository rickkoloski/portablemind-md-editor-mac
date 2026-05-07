// D24.2 phase 2 — Pass 2 of the responsive-table-column algorithm.
//
// Pure function. No mutable state; no side effects. Given per-column
// (min, max) content widths and a viewport width, returns per-column
// applied widths.
//
// Algorithm (per `docs/current_work/specs/d24.2_slack_proportional_columns_spec.md`):
//
//   1. Fits regime — `Σ max ≤ viewport`: every col at max.
//   2. Overflow regime — `Σ min ≥ viewport`: every col at min, then
//      post-pass floor clamp at `min(max, minWidthFloor)`. Sum may
//      exceed viewport — Q2 says floor wins.
//   3. Slack regime (between fits and overflow):
//      a. **Q8 pre-lock** — greedy iterate: pick the unlocked column
//         with smallest `max` such that `max ≤ narrowThreshold` AND
//         locking it leaves enough room for the other flex cols' mins
//         (`pool_after ≥ Σ min(remaining_flex)`). Repeat until no
//         qualifying candidate remains.
//      b. **Slack distribution** — every flex col gets its `min` plus
//         a share of the surplus proportional to its `slack = max - min`.
//         Degenerate (total slack = 0): split surplus equally.
//      c. Post-pass floor clamp at `min(max, minWidthFloor)`.

import CoreGraphics

enum TableColumnDistribution {

    /// Default Q8 narrow-column threshold — tunable per-call. 120pt
    /// covers typical structured-data column maxes (dates, IDs, statuses,
    /// short owners) while excluding prose-y description columns.
    static let defaultNarrowThreshold: CGFloat = 120

    /// Distribute `viewportWidth` across `measurements`.
    ///
    /// - Parameter measurements: per-column `(min, max)` content widths.
    ///   Caller must pre-cap each `maxContent` at `viewportWidth` per
    ///   D24's Q8 (viewport cap) — this function trusts its inputs.
    /// - Parameter viewportWidth: container width inside the editor's
    ///   text container, in points.
    /// - Parameter minWidthFloor: per-column floor. A column never
    ///   shrinks below `min(maxContent, minWidthFloor)`. Default 60.
    /// - Parameter narrowThreshold: D24.2 Q8 threshold. Columns whose
    ///   `maxContent` is below this lock at max regardless of slack.
    ///   Default 120; tunable so a future setting can dial spec-parity.
    /// - Returns: applied widths summing to ≤ `viewportWidth` in fits +
    ///   slack regimes; > `viewportWidth` only in floor-wins / overflow
    ///   cases per spec Q2.
    static func distribute(
        measurements: [ColumnContentMeasurement],
        viewportWidth: CGFloat,
        minWidthFloor: CGFloat = 60,
        narrowThreshold: CGFloat = defaultNarrowThreshold
    ) -> [CGFloat] {

        if measurements.isEmpty { return [] }

        let sumMin = measurements.reduce(CGFloat(0)) { $0 + $1.minContent }
        let sumMax = measurements.reduce(CGFloat(0)) { $0 + $1.maxContent }

        // Regime 1 — fits. Everyone at max.
        if sumMax <= viewportWidth {
            return measurements.map { $0.maxContent }
        }

        // Regime 2 — overflow. Even mins don't fit.
        if sumMin >= viewportWidth {
            var widths = measurements.map { $0.minContent }
            applyFloorClamp(
                widths: &widths,
                measurements: measurements,
                minWidthFloor: minWidthFloor)
            return widths
        }

        // Regime 3 — slack. Q8 pre-lock + slack-proportional flex.
        var locked: Set<Int> = []
        while true {
            let lockedMaxSum = locked.reduce(CGFloat(0)) { $0 + measurements[$1].maxContent }
            let lockedMinSum = locked.reduce(CGFloat(0)) { $0 + measurements[$1].minContent }
            let pool = viewportWidth - lockedMaxSum
            var best: Int? = nil
            for i in measurements.indices where !locked.contains(i) {
                let c = measurements[i]
                if c.maxContent > narrowThreshold { continue }
                // Locking c leaves pool_after = pool - max(c). Need that
                // to be ≥ sum of mins of all OTHER flex cols (everyone
                // not locked, excluding c itself).
                let poolAfter = pool - c.maxContent
                let remainingMin = sumMin - lockedMinSum - c.minContent
                if poolAfter >= remainingMin {
                    if best == nil || c.maxContent < measurements[best!].maxContent {
                        best = i
                    }
                }
            }
            guard let b = best else { break }
            locked.insert(b)
        }

        var widths: [CGFloat] = Array(repeating: 0, count: measurements.count)
        for i in locked {
            widths[i] = measurements[i].maxContent
        }
        let flexIndices = measurements.indices.filter { !locked.contains($0) }
        if !flexIndices.isEmpty {
            let lockedSum = locked.reduce(CGFloat(0)) { $0 + measurements[$1].maxContent }
            let flexPool = viewportWidth - lockedSum
            let flexSumMin = flexIndices.reduce(CGFloat(0)) { $0 + measurements[$1].minContent }
            let surplus = flexPool - flexSumMin
            let totalSlack = flexIndices.reduce(CGFloat(0)) { $0 + measurements[$1].slack }
            for i in flexIndices {
                let m = measurements[i]
                let share: CGFloat
                if totalSlack > 0 {
                    share = m.slack / totalSlack * surplus
                } else {
                    // Degenerate: every flex col has slack=0 (min == max).
                    // Split surplus equally.
                    share = surplus / CGFloat(flexIndices.count)
                }
                widths[i] = m.minContent + share
            }
        }

        applyFloorClamp(
            widths: &widths,
            measurements: measurements,
            minWidthFloor: minWidthFloor)
        return widths
    }

    /// Per spec Q3: post-pass clamp at `min(maxContent, minWidthFloor)`.
    /// Columns whose `maxContent < minWidthFloor` stay at `maxContent`
    /// (don't blow up to the floor); other columns are pulled up to
    /// `minWidthFloor` if slack distribution dropped them lower.
    private static func applyFloorClamp(
        widths: inout [CGFloat],
        measurements: [ColumnContentMeasurement],
        minWidthFloor: CGFloat
    ) {
        for i in widths.indices {
            let effFloor = min(measurements[i].maxContent, minWidthFloor)
            if widths[i] < effFloor {
                widths[i] = effFloor
            }
        }
    }
}
