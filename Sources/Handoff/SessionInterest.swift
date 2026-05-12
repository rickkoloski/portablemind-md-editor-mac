import AppKit
import Foundation

/// D30 — one session's registered interest in a tab.
///
/// v1 caps the active set on any `EditorDocument` at 1 (current
/// dogfood reality: parallel CC sessions own disjoint doc sets, so
/// the session↔doc relationship is naturally 1:1). The array shape
/// on `EditorDocument.interestedSessions` is forward-compat insurance
/// for a possible future n:m UX; the v1 surface enforces 1:1.
struct SessionInterest: Identifiable {
    let sessionID: String
    let registeredAt: Date
    let label: String?
    let color: NSColor

    var id: String { sessionID }

    static func make(sessionID: String, label: String? = nil) -> SessionInterest {
        SessionInterest(
            sessionID: sessionID,
            registeredAt: Date(),
            label: label,
            color: deterministicColor(for: sessionID))
    }

    /// FNV-1a 64-bit hash → hue. Same `sessionID` → same color across
    /// runs, so the tab badge's color is stable visual identity for a
    /// given session.
    static func deterministicColor(for sessionID: String) -> NSColor {
        var hash: UInt64 = 1469598103934665603
        for byte in sessionID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        let hue = CGFloat(hash % 360) / 360.0
        return NSColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1.0)
    }
}
