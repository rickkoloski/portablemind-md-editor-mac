import Foundation

/// Identifiers for the commands the app accepts from outside — CLI
/// invocation, URL scheme events, future MCP tool calls. The raw-
/// value string appears in the `md-editor://<identifier>?…` URL host
/// position.
///
/// Per engineering-standards §2.4, every external-entry command is
/// registered once in `CommandSurface`. Add a case here, declare a
/// type conforming to `ExternalCommand`, and register it — no other
/// file should grow a handler.
enum ExternalCommandIdentifier: String {
    case openFile = "open"
    case openFolder = "open-folder"
}

/// An external command. Implementations operate on the
/// `WorkspaceStore` — the only app-wide state external callers can
/// reach. If a command needs access to something else (e.g., the
/// active editor's selection), expose it through `WorkspaceStore`
/// first rather than bypassing this boundary.
@MainActor
protocol ExternalCommand {
    static var identifier: ExternalCommandIdentifier { get }
    static func execute(params: [String: String], in workspace: WorkspaceStore)
}
