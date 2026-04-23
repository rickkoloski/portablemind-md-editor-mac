import SwiftUI

/// Shown when no document is focused in the workspace — either no
/// files are open, or the last tab was closed.
struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No file open")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick a file from the sidebar, or use File → Open…")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityIdentifier(AccessibilityIdentifiers.emptyEditor)
    }
}
