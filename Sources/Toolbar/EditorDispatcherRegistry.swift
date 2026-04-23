import AppKit
import Combine

/// Pragmatic single-window dispatch bridge between the global SwiftUI
/// toolbar (and View menu) and the currently-active editor's command
/// dispatcher. The `EditorContainer` coordinator registers its text
/// view here on creation; toolbar buttons read `activeDispatch` and
/// call it.
///
/// When md-editor gains multi-window support, migrate to
/// `@FocusedValue(\.editorDispatch)` (see
/// `EditorDispatcherFocusedValue.swift`) and retire this registry.
@MainActor
final class EditorDispatcherRegistry: ObservableObject {
    static let shared = EditorDispatcherRegistry()

    @Published private(set) var activeDispatch: ((String) -> Void)?

    func register(for textView: NSTextView) {
        activeDispatch = { [weak textView] identifier in
            guard let textView else { return }
            _ = CommandDispatcher.shared.dispatch(identifier: identifier, in: textView)
        }
    }

    func deregister() {
        activeDispatch = nil
    }

    private init() {}
}
