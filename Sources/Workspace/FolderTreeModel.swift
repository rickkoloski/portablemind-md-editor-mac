import Foundation

/// A node in the workspace folder tree.
struct FolderNode: Identifiable, Hashable {
    /// The file URL is also the stable identity.
    var id: URL { url }
    let url: URL
    let name: String
    let isDirectory: Bool
}

/// Shared filter rules. Anything starting with `.` is hidden, plus a
/// small allowlist of well-known directories we don't want cluttering
/// the sidebar. User-visible "show hidden" toggle is out of scope
/// for D6.
enum FolderFilter {
    static let excludedNames: Set<String> = [
        ".git",
        ".build",
        ".build-xcode",
        ".swiftpm",
        ".DS_Store",
        "DerivedData",
        "node_modules",
        "Pods",
    ]

    static func shouldShow(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        if excludedNames.contains(name) { return false }
        return true
    }
}

/// Lazy directory walk — returns direct children only. Sidebar view
/// calls this on expand; full tree is never materialized eagerly.
enum FolderTreeLoader {
    static func children(of url: URL) -> [FolderNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let nodes = contents
            .filter(FolderFilter.shouldShow)
            .compactMap { childURL -> FolderNode? in
                let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey])
                    .isDirectory) ?? false
                return FolderNode(
                    url: childURL,
                    name: childURL.lastPathComponent,
                    isDirectory: isDir
                )
            }

        // Directories first, then files; alphabetic within each group,
        // case-insensitive.
        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory  // true < false → dirs first
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
