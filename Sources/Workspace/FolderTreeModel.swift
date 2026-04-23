import Foundation

/// A node in the workspace folder tree. `children` is a lazy
/// computed property so SwiftUI's `OutlineGroup(_:children:)` (which
/// requires a KeyPath target) can traverse the tree without eager
/// materialization.
struct FolderNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let isDirectory: Bool

    /// OutlineGroup KeyPath target. nil → leaf (no disclosure triangle).
    var children: [FolderNode]? {
        guard isDirectory else { return nil }
        return FolderTreeLoader.children(of: url)
    }

    // Hashable / Equatable based on stored properties only, so the
    // computed `children` (which re-walks the filesystem) doesn't
    // participate in identity.
    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.url == rhs.url && lhs.name == rhs.name && lhs.isDirectory == rhs.isDirectory
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(name)
        hasher.combine(isDirectory)
    }
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
