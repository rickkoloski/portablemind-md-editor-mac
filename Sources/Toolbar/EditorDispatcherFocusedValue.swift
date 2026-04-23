import SwiftUI

/// FocusedValue key for command dispatch — the proper SwiftUI-idiomatic
/// path for routing toolbar / menu commands to the currently-focused
/// editor. Currently a stub: D5 uses `EditorDispatcherRegistry` for the
/// single-window case (simpler to wire through an NSViewRepresentable).
/// When multi-window support lands in a later deliverable, migrate the
/// toolbar and menu items to read this FocusedValue instead.
struct EditorDispatcherKey: FocusedValueKey {
    typealias Value = (String) -> Void
}

extension FocusedValues {
    var editorDispatch: EditorDispatcherKey.Value? {
        get { self[EditorDispatcherKey.self] }
        set { self[EditorDispatcherKey.self] = newValue }
    }
}
