// D24 phase 3 — Pass 2 of the responsive-table-column algorithm.
//
// Pure function. No mutable state; no side effects. Given per-column natural
// widths (caller pre-caps each entry at viewport width per Q8) and a viewport
// width, returns per-column applied widths.
//
// Spec: docs/current_work/specs/d24_responsive_table_columns_spec.md §Algorithm.
// Plan: docs/current_work/planning/d24_responsive_table_columns_plan.md §Phase 3.

import CoreGraphics

enum TableColumnDistribution {

    /// Distribute `viewportWidth` across `naturalWidths` proportionally,
    /// locking any column whose natural width is at-or-below the equal-share
    /// threshold and flexing the remaining columns over what's left.
    ///
    /// - Parameter naturalWidths: per-column natural width. Caller must
    ///   pre-cap each entry at `viewportWidth` per Q8 — this function trusts
    ///   its inputs.
    /// - Parameter viewportWidth: container width inside the editor's text
    ///   container, in points.
    /// - Parameter minWidthFloor: per-column floor. A column is never shrunk
    ///   below `min(natural_width, minWidthFloor)`. Default 60pt.
    /// - Returns: applied widths summing to ≤ `viewportWidth` unless the
    ///   floor-wins branch fires (`viewportWidth < minWidthFloor × n`), in
    ///   which case the result sums to exactly `Σ min_width(col_i)` —
    ///   floors stand even at the cost of running past viewport.
    static func distribute(
        naturalWidths: [CGFloat],
        viewportWidth: CGFloat,
        minWidthFloor: CGFloat = 60
    ) -> [CGFloat] {

        // Empty / degenerate inputs.
        if naturalWidths.isEmpty { return [] }
        if viewportWidth <= 0 {
            return naturalWidths.map { min($0, minWidthFloor) }
        }

        let totalNatural = naturalWidths.reduce(0, +)

        // Everything fits — lock every column at natural width. (Spec Q6.)
        if totalNatural <= viewportWidth {
            return naturalWidths
        }

        // Lock-in pass.
        let n = naturalWidths.count
        var widths = naturalWidths   // overwritten for flex cols below
        var locked = Set<Int>()

        while true {
            let unlockedCount = n - locked.count
            if unlockedCount == 0 { break }
            let lockedTotal = locked.reduce(CGFloat(0)) { $0 + widths[$1] }
            let flexPool = viewportWidth - lockedTotal
            let equalShare = flexPool / CGFloat(unlockedCount)
            var newLocks: [Int] = []
            for i in 0..<n where !locked.contains(i) {
                if naturalWidths[i] <= equalShare {
                    newLocks.append(i)
                }
            }
            if newLocks.isEmpty { break }
            for i in newLocks {
                widths[i] = naturalWidths[i]
                locked.insert(i)
            }
        }

        // Distribute flex pool proportionally to natural widths.
        let flexIndices = (0..<n).filter { !locked.contains($0) }
        if flexIndices.isEmpty {
            return widths
        }
        let flexTotalNatural = flexIndices.reduce(CGFloat(0)) {
            $0 + naturalWidths[$1]
        }
        let lockedTotal = locked.reduce(CGFloat(0)) { $0 + widths[$1] }
        let flexPool = max(0, viewportWidth - lockedTotal)

        // Initial proportional assignment, then floor.
        for i in flexIndices {
            let share = flexTotalNatural > 0
                ? (naturalWidths[i] / flexTotalNatural) * flexPool
                : flexPool / CGFloat(flexIndices.count)
            let floor = min(naturalWidths[i], minWidthFloor)
            widths[i] = max(floor, share)
        }

        // Floor-wins overflow check. Only fires when floors raised some
        // columns above their proportional share — common when
        // viewport_width < minWidthFloor × n. Reduce above-floor flex
        // columns proportionally to absorb the excess; if even that's not
        // enough, accept the overflow per spec ("floor wins").
        let total = widths.reduce(0, +)
        if total > viewportWidth + .ulpOfOne {
            var excess = total - viewportWidth
            // Multi-pass reduction: each pass cuts proportionally from
            // columns currently above their floor. Repeats because cutting
            // can drive a column to its floor and shift the proportional
            // base of the remaining cuts. Bounded by `flexIndices.count`
            // iterations.
            for _ in 0..<flexIndices.count {
                if excess <= .ulpOfOne { break }
                let aboveFloor: [(Int, CGFloat)] = flexIndices.compactMap { i in
                    let f = min(naturalWidths[i], minWidthFloor)
                    let headroom = widths[i] - f
                    return headroom > 0 ? (i, headroom) : nil
                }
                let reducible = aboveFloor.reduce(CGFloat(0)) { $0 + $1.1 }
                if reducible <= 0 { break }
                let cut = min(excess, reducible)
                for (i, headroom) in aboveFloor {
                    let share = (headroom / reducible) * cut
                    widths[i] -= share
                }
                excess = widths.reduce(0, +) - viewportWidth
            }
            // Clamp tiny floating-point residuals so any column that should
            // be at its floor is exactly at its floor.
            for i in flexIndices {
                let f = min(naturalWidths[i], minWidthFloor)
                if widths[i] < f {
                    widths[i] = f
                }
            }
        }

        return widths
    }
}
