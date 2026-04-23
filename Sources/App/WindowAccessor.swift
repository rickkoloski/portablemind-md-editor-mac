import AppKit
import SwiftUI

/// Bridges a SwiftUI view to its owning `NSWindow`. Attach via
/// `.background(WindowAccessor { window in … })`. The closure runs on
/// every SwiftUI update pass, so it can reflect observed state into
/// window-level AppKit properties (like `toolbar.isVisible`) that
/// SwiftUI doesn't expose cleanly on its own.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            onResolve(window)
        }
    }
}
