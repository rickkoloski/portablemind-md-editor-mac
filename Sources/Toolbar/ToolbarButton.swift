import SwiftUI

/// Generic toolbar button. One per direct `ToolbarAction`. Reads the
/// active dispatcher from `EditorDispatcherRegistry`; disables when no
/// editor is focused.
struct ToolbarButton: View {
    let action: ToolbarAction
    @ObservedObject private var registry = EditorDispatcherRegistry.shared

    var body: some View {
        Button(action: invoke) {
            Label(action.title, systemImage: action.systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(red: 222/255, green: 222/255, blue: 222/255))
        }
        .help(action.helpText)
        .disabled(registry.activeDispatch == nil)
        .accessibilityIdentifier(action.accessibilityIdentifier)
        .accessibilityLabel(action.title)
    }

    private func invoke() {
        registry.activeDispatch?(action.commandIdentifier)
    }
}
