// D24 phase 2 / D24.2 phase 1 — per-column content-width cache.
//
// Cache value: a (min, max) pair of CGFloats per column. The hash key is
// purely content-derived (header text + body row texts in render order);
// viewport width is applied as caps and distribution downstream. The cache
// is therefore valid across viewport-resize cycles; only column-content
// edits cause a miss.
//
// Concurrency: main-thread only. The render path runs inside NSTextStorage
// processing on the main thread; the harness reader is @MainActor. A plain
// dict is sufficient — no actor isolation, no lock.

import Foundation
import CoreGraphics

/// A column's content-derived width pair, used by the D24.2 distribution
/// algorithm.
///
/// - `minContent` — the column's widest unbreakable atom. Per D24.2 Q1:
///   the longest contiguous run that has no soft-break opportunity (no
///   whitespace, no `-`, no `/`, no `.`). A column never shrinks below
///   `minContent` without char-wrap.
/// - `maxContent` — the column's longest single-line shaped width across
///   header + body cells (== D24's `naturalWidth`, renamed for spec parity).
struct ColumnContentMeasurement: Equatable {
    let minContent: CGFloat
    let maxContent: CGFloat

    /// Difference between max and min content widths. Drives the slack-
    /// proportional surplus distribution in `TableColumnDistribution`.
    var slack: CGFloat { max(0, maxContent - minContent) }
}

final class TableNaturalWidthCache {
    static let shared = TableNaturalWidthCache()

    private var entries: [Int: ColumnContentMeasurement] = [:]
    private var hits: Int = 0
    private var misses: Int = 0

    private init() {}

    /// Looks up the cached measurement for `hash`; computes via `compute`
    /// on miss and stores the result. Returns `(measurement, hit)` so
    /// callers (notably the harness) can report cache effectiveness.
    func measurementOrCompute(
        forContentHash hash: Int,
        compute: () -> ColumnContentMeasurement
    ) -> (measurement: ColumnContentMeasurement, hit: Bool) {
        if let cached = entries[hash] {
            hits += 1
            return (cached, true)
        }
        let m = compute()
        entries[hash] = m
        misses += 1
        return (m, false)
    }

    func stats() -> (hits: Int, misses: Int, entries: Int) {
        return (hits, misses, entries.count)
    }

    func reset() {
        entries.removeAll()
        hits = 0
        misses = 0
    }
}
