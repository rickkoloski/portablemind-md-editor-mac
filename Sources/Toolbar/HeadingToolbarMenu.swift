import SwiftUI

/// Dropdown menu exposing Body + Heading 1–6. Each item dispatches a
/// distinct mutation command identifier.
struct HeadingToolbarMenu: View {
    @ObservedObject private var registry = EditorDispatcherRegistry.shared

    var body: some View {
        Menu {
            menuItem("Body", id: AccessibilityIdentifiers.headingMenuBody,
                     command: BodyMutation.identifier)
            menuItem("Heading 1", id: AccessibilityIdentifiers.headingMenuH1,
                     command: Heading1Mutation.identifier)
            menuItem("Heading 2", id: AccessibilityIdentifiers.headingMenuH2,
                     command: Heading2Mutation.identifier)
            menuItem("Heading 3", id: AccessibilityIdentifiers.headingMenuH3,
                     command: Heading3Mutation.identifier)
            menuItem("Heading 4", id: AccessibilityIdentifiers.headingMenuH4,
                     command: Heading4Mutation.identifier)
            menuItem("Heading 5", id: AccessibilityIdentifiers.headingMenuH5,
                     command: Heading5Mutation.identifier)
            menuItem("Heading 6", id: AccessibilityIdentifiers.headingMenuH6,
                     command: Heading6Mutation.identifier)
        } label: {
            Label("Heading", systemImage: "textformat")
                .labelStyle(.iconOnly)
        }
        .help("Heading")
        .disabled(registry.activeDispatch == nil)
        .accessibilityIdentifier(AccessibilityIdentifiers.toolbarHeadingMenu)
        .accessibilityLabel("Heading")
    }

    @ViewBuilder
    private func menuItem(_ title: String, id: String, command: String) -> some View {
        Button(title) { registry.activeDispatch?(command) }
            .accessibilityIdentifier(id)
    }
}
