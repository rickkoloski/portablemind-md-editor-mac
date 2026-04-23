import SwiftUI

/// Horizontal strip of open-document tabs. Each tab has a filename
/// label and a close `×`. Overflow scrolls horizontally per spec OQ
/// #2 default.
struct TabBarView: View {
    @ObservedObject var tabs: TabStore

    var body: some View {
        // D6 finding: a SwiftUI horizontal ScrollView around this
        // HStack swallowed mouse clicks on macOS 15 — tabs rendered
        // but never received tap events. Removing the ScrollView
        // unblocked clicks. Overflow (more tabs than fit) now clips;
        // horizontal-scroll-with-working-clicks is a polish deliverable
        // for later (candidates: chevron dropdown, native NSStackView
        // bridging, or a ScrollView variant with explicit
        // .scrollIndicators / hit-test overrides).
        HStack(spacing: 4) {
            ForEach(Array(tabs.documents.enumerated()), id: \.element.id) { index, doc in
                TabItemView(
                    document: doc,
                    isFocused: tabs.focusedIndex == index,
                    onFocus: { tabs.focus(id: doc.id) },
                    onClose: { tabs.close(id: doc.id) }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier(AccessibilityIdentifiers.tabBar)
    }
}

private struct TabItemView: View {
    @ObservedObject var document: EditorDocument
    let isFocused: Bool
    let onFocus: () -> Void
    let onClose: () -> Void

    var body: some View {
        // Outer Button owns the tab's focus action. Inner close Button
        // is a sibling inside the label; SwiftUI hit-tests the close
        // button first for its bounds (because it's a nested Button),
        // so the `onFocus` outer action doesn't fire when the user
        // actually clicks the `×`. Both use .buttonStyle(.plain) so
        // neither draws the default button chrome.
        Button(action: onFocus) {
            HStack(spacing: 6) {
                if document.externallyDeleted {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("File no longer exists on disk")
                }

                Text(document.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .frame(maxWidth: 160, alignment: .leading)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityIdentifiers.tabCloseButton(documentID: document.id))
                .accessibilityLabel("Close \(document.displayName)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFocused
                          ? Color(nsColor: .controlBackgroundColor)
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2),
                            lineWidth: isFocused ? 1 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityIdentifiers.tabButton(documentID: document.id))
        .accessibilityLabel(document.displayName)
    }
}
