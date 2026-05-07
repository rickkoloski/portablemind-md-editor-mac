// D23 — shared file-management service that the SaveAsSheet UI AND the
// harness `pm_save_as` action both call. Centralizes the "create on
// connector + rebind the open tab" sequence so the modal and the
// harness can't drift in semantics.
//
// Design: enum-as-namespace, @MainActor for the document mutation step.
// All operations are async because the connector calls are.

import Foundation

@MainActor
enum PMFileOperations {

    /// Save `doc`'s current buffer as a new file at `parent / name`.
    ///
    /// Side effects (Q2 — switch existing tab to new node):
    /// - Calls `parent.connector.createFile(in: parent, name: name, bytes: doc.source)`.
    /// - Updates `doc.origin`, `doc.connectorNode`, and `doc.url` so the
    ///   open tab now points at the new file.
    /// - Sets `doc.lastSavedSource = doc.source` (no longer dirty).
    ///
    /// Returns the new node so callers can splice it into the sidebar
    /// tree. Throws `ConnectorError` on failure (the modal surfaces
    /// inline; the harness writes the error to its result file).
    static func saveAs(doc: EditorDocument,
                       to parent: ConnectorNode,
                       name: String) async throws -> ConnectorNode {
        let bytes = Data(doc.source.utf8)
        let newNode = try await parent.connector.createFile(
            in: parent, name: name, bytes: bytes)

        let (newOrigin, newURL) = mapNodeToOrigin(
            newNode, parentConnector: parent.connector)
        doc.updateAfterSaveAs(
            newOrigin: newOrigin,
            newConnectorNode: newNode,
            newURL: newURL)
        return newNode
    }

    // MARK: - Helpers

    /// Translate a freshly-created `ConnectorNode` into the corresponding
    /// `(EditorDocument.Origin, URL?)` pair. PM connectors yield
    /// `.portableMind(...)` with no URL; Local yields `.local` with a
    /// file URL. Unrecognized connector kinds fall back to `.local`
    /// with a best-effort URL — matches D18's "Local is the default"
    /// posture.
    private static func mapNodeToOrigin(
        _ node: ConnectorNode,
        parentConnector: any Connector
    ) -> (EditorDocument.Origin, URL?) {
        if parentConnector is PortableMindConnector,
           let fileID = parsePMFileID(node.id) {
            let origin = EditorDocument.Origin.portableMind(
                connectorID: parentConnector.id,
                fileID: fileID,
                displayPath: node.path)
            return (origin, nil)
        }
        return (.local, URL(fileURLWithPath: node.path))
    }

    /// Parse the numeric LlmFile id out of a PortableMind `ConnectorNode.id`
    /// (format `"<connectorID>:file:<numericID>"`). Mirrors the parser
    /// in PortableMindConnector but lives here to keep PMFileOperations
    /// independent of the connector's internals — caller passes node id.
    private static func parsePMFileID(_ nodeID: String) -> Int? {
        let parts = nodeID.split(separator: ":")
        guard parts.count >= 3, parts[parts.count - 2] == "file",
              let fileID = Int(parts[parts.count - 1])
        else { return nil }
        return fileID
    }
}
