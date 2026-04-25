// TEST-HARNESS: This entire file exists for debug-only test driving.
// Search the codebase for `TEST-HARNESS:` to find every accommodation
// made for autonomous testing. Strip these by deleting the marked
// blocks if/when the harness is no longer needed.
//
// The harness exists so an external driver (Claude Code or a test
// script) can interact with the running app via file-based commands
// without simulated mouse/key events that depend on the app being
// frontmost. Conceptually mirrors the spike harness in
// `spikes/d12_cell_caret/`.
//
// Compiled out of release builds via `#if DEBUG`.

#if DEBUG

import AppKit
import Combine

/// Singleton that tracks the currently-active editor `NSTextView`.
/// `EditorContainer` registers its text view here on creation so the
/// harness command poller can inspect / drive editor state.
@MainActor
final class HarnessActiveSink {
    static let shared = HarnessActiveSink()

    /// Weak so deallocation isn't blocked by the registry.
    private(set) weak var activeTextView: NSTextView?

    func register(_ textView: NSTextView) {
        activeTextView = textView
    }

    func deregister() {
        activeTextView = nil
    }

    private init() {}
}

#endif
