// D24 phase 2 — per-column natural-width cache.
//
// Key: a content hash composed of the column's header and body cell texts
// in render order. The hash is purely content-derived; viewport width is
// applied as a cap downstream during distribution (Q8 + Pass 2). The cache
// is therefore valid across viewport-resize cycles; only column-content
// edits (which change the hash) cause a miss.
//
// Concurrency: main-thread only. The render path runs inside NSTextStorage
// processing on the main thread; the harness reader is @MainActor. A plain
// dict is sufficient — no actor isolation, no lock.

import Foundation
import CoreGraphics

final class TableNaturalWidthCache {
    static let shared = TableNaturalWidthCache()

    private var entries: [Int: CGFloat] = [:]
    private var hits: Int = 0
    private var misses: Int = 0

    private init() {}

    /// Looks up the cached width for `hash`; computes via `compute` on miss
    /// and stores the result. Returns `(width, hit)` so callers (notably the
    /// harness) can report cache effectiveness.
    func widthOrCompute(forContentHash hash: Int,
                        compute: () -> CGFloat) -> (width: CGFloat, hit: Bool) {
        if let cached = entries[hash] {
            hits += 1
            return (cached, true)
        }
        let width = compute()
        entries[hash] = width
        misses += 1
        return (width, false)
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
