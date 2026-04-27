// D19 phase 2 — minimal multipart/form-data builder for URLSession.
//
// Harmoniq's `PATCH /api/v1/llm_files/:id` requires a multipart-encoded
// body with the file content under the `llm_file[file]` part. URLSession
// has no built-in multipart helper; this is the smallest thing that
// works for our case (single file part, opt-in extra text fields).
//
// Boundary uses a UUID-derived random token. Caller is expected to pass
// `(body, contentType)` together — the contentType string includes the
// boundary so the server can parse the body correctly.

import Foundation

struct MultipartFormDataBuilder {
    private(set) var body: Data = Data()
    let boundary: String

    init(boundary: String = "Boundary-" + UUID().uuidString) {
        self.boundary = boundary
    }

    /// Top-level Content-Type header value. Includes the boundary.
    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Append a file part. `name` is the form-field name (e.g.
    /// `llm_file[file]`); `filename` is the basename Harmoniq stores
    /// alongside the blob.
    mutating func appendFile(name: String,
                             filename: String,
                             contentType: String,
                             data: Data) {
        body.append("--\(boundary)\r\n")
        body.append(
            "Content-Disposition: form-data; name=\"\(name)\"; "
            + "filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    /// Append a plain text field. Used for sibling params like
    /// `llm_file[title]` if the caller wants to update metadata
    /// alongside content. D19 phase 2 doesn't use this; phase-5 / future
    /// rename-and-move deliverable will.
    mutating func appendText(name: String, value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append(value)
        body.append("\r\n")
    }

    /// Close the multipart body. Call exactly once after all parts.
    mutating func finalize() {
        body.append("--\(boundary)--\r\n")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
