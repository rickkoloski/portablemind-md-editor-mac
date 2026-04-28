// D21 — path display + copy helpers for the workspace tree.
//
// Used by row context menus (Copy Path / Copy Relative Path), the
// root row's hover tooltip, and the "Show Path in Tree" toggle on the
// root context menu.
//
// Convention for local paths: collapse the user's home directory to
// `~`. Anything outside home shows the full absolute path. Mirrors
// shell convention.

import AppKit
import Foundation

enum PathFormatting {
    /// Format a local filesystem path for display: collapse the user's
    /// home directory to `~`. Anything outside home gets the full path.
    static func displayLocalPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Format a node's path for "Copy Path" — the absolute / canonical
    /// form a user (or another agent) can use to navigate back to this
    /// node.
    /// - Local: home-relative `~` form when inside home, else full
    ///   absolute path.
    /// - PortableMind (and other connectors): the path verbatim — it's
    ///   already canonical relative to the connector's tree root.
    static func absolutePathForCopy(_ node: ConnectorNode) -> String {
        if node.connector.id == "local" {
            return displayLocalPath(node.path)
        }
        return node.path
    }

    /// Format a node's path for "Copy Relative Path" — relative to the
    /// connector's root.
    /// - Local: relative to the workspace folder.
    /// - PortableMind: PM path with the leading `/` stripped (PM paths
    ///   are already root-relative; this just removes the slash for
    ///   clean concatenation in agent prompts and other docs).
    static func relativePathForCopy(_ node: ConnectorNode) -> String {
        if node.connector.id == "local" {
            let rootPath = node.connector.rootNode.path
            if node.path == rootPath { return "" }
            let withSlash = rootPath + "/"
            if node.path.hasPrefix(withSlash) {
                return String(node.path.dropFirst(withSlash.count))
            }
            return node.path
        }
        if node.path.hasPrefix("/") {
            return String(node.path.dropFirst())
        }
        return node.path
    }

    /// Copy a string to the system clipboard.
    static func copyToClipboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
