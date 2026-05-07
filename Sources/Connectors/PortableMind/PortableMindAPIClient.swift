// D18 phase 2 — HTTP client for Harmoniq's REST API. URLSession +
// bearer-token auth; reads token from KeychainTokenStore on each call
// so a token rotation (e.g. user pastes a new one via Debug menu) takes
// effect immediately.
//
// Two-layer auth:
//   1. Most endpoints require the bearer token (Authorization header).
//   2. ActiveStorage signed blob URLs from `LlmFile.url` are NOT
//      bearer-protected — they carry their own signature in the URL.
//      Use `fetchSignedBlob` for those (no Authorization header).

import Foundation

final class PortableMindAPIClient {
    private let session: URLSession
    private let tokens: KeychainTokenStore

    init(session: URLSession = .shared,
         tokens: KeychainTokenStore = .shared) {
        self.session = session
        self.tokens = tokens
    }

    // MARK: - Public API

    /// `GET /api/v1/users/current` — returns the authenticated user
    /// including their `tenant_id` (drives the cross-tenant badge
    /// predicate in `PortableMindConnector`).
    func currentUser() async throws -> CurrentUserDTO {
        let url = base("/users/current")
        let resp: CurrentUserResponse = try await getJSON(url: url)
        guard let user = resp.user else {
            throw ConnectorError.server(
                status: 200, message: "users/current: missing user payload")
        }
        return user
    }

    /// `GET /api/v1/llm_directories?parent_path=…&cross_tenant=…&limit=-1`
    func listDirectories(parentPath: String?,
                         crossTenant: Bool = true) async throws -> [DirectoryDTO] {
        var comps = URLComponents(
            url: base("/llm_directories"),
            resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "-1"),
            URLQueryItem(name: "cross_tenant", value: crossTenant ? "true" : "false"),
        ]
        if let parentPath, !parentPath.isEmpty {
            items.append(URLQueryItem(name: "parent_path", value: parentPath))
        }
        comps.queryItems = items
        let resp: ListDirectoriesResponse = try await getJSON(url: comps.url!)
        return resp.llm_directories ?? []
    }

    /// `GET /api/v1/llm_files?directory_path=…`
    func listFiles(directoryPath: String) async throws -> [FileDTO] {
        var comps = URLComponents(
            url: base("/llm_files"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "limit", value: "-1"),
            URLQueryItem(name: "directory_path", value: directoryPath),
        ]
        let resp: ListFilesResponse = try await getJSON(url: comps.url!)
        return resp.llm_files ?? []
    }

    /// `GET /api/v1/llm_files/:id` — file metadata including the
    /// signed `url` for blob fetch. The `url` expires 1h after
    /// generation; refetch if needed.
    func fetchFileMeta(fileID: Int) async throws -> FileDTO {
        let url = base("/llm_files/\(fileID)")
        let resp: LlmFileShowResponse = try await getJSON(url: url)
        guard let file = resp.llm_file else {
            throw ConnectorError.server(
                status: 200, message: "llm_files/\(fileID): missing payload")
        }
        return file
    }

    /// One-shot read: meta → signed-URL GET → bytes.
    func fetchFileContent(fileID: Int) async throws -> Data {
        let meta = try await fetchFileMeta(fileID: fileID)
        guard let urlString = meta.url, let url = URL(string: urlString) else {
            throw ConnectorError.server(
                status: 200, message: "llm_files/\(fileID): missing url")
        }
        return try await fetchSignedBlob(url: url)
    }

    /// `PATCH /api/v1/llm_files/:id` — replace the file's content with
    /// `bytes`. multipart/form-data; the file part is named
    /// `llm_file[file]`. Returns the refreshed FileDTO with a fresh
    /// signed URL (20-minute expiry per Harmoniq). The server's
    /// `updated_at` in the response is the new server-side mtime; the
    /// caller should record it as the next `lastSeenUpdatedAt` for
    /// conflict detection.
    func updateFile(fileID: Int,
                    bytes: Data,
                    contentType: String = "text/markdown",
                    filename: String = "content.md")
        async throws -> FileDTO
    {
        var builder = MultipartFormDataBuilder()
        builder.appendFile(
            name: "llm_file[file]",
            filename: filename,
            contentType: contentType,
            data: bytes)
        builder.finalize()

        let url = base("/llm_files/\(fileID)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json",
                         forHTTPHeaderField: "Accept")
        request.setValue(builder.contentType,
                         forHTTPHeaderField: "Content-Type")
        guard let token = try tokens.load(), !token.isEmpty else {
            throw ConnectorError.unauthenticated
        }
        request.setValue("Bearer \(token)",
                         forHTTPHeaderField: "Authorization")
        if let identifier = JWTPayload.tenantEnterpriseIdentifier(from: token) {
            request.setValue(identifier, forHTTPHeaderField: "X-Tenant-ID")
        }
        request.httpBody = builder.body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConnectorError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.network(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299:
            do {
                let resp = try JSONDecoder().decode(
                    LlmFileShowResponse.self, from: data)
                guard let file = resp.llm_file else {
                    throw ConnectorError.server(
                        status: http.statusCode,
                        message: "PATCH llm_files/\(fileID): missing payload")
                }
                return file
            } catch {
                throw ConnectorError.server(
                    status: http.statusCode,
                    message: "decode failed: \(error)")
            }
        case 401, 403:
            let body = String(data: data, encoding: .utf8)
            throw ConnectorError.writeForbidden(
                body ?? "HTTP \(http.statusCode)")
        case 402:
            // Storage quota — Harmoniq returns
            // {error_code: "DOCUMENT_STORAGE_LIMIT_EXCEEDED", message: …}
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ConnectorError.storageQuotaExceeded(body)
        default:
            let body = String(data: data, encoding: .utf8)
            throw ConnectorError.server(
                status: http.statusCode, message: body)
        }
    }

    // MARK: - D23 file management

    /// `POST /api/v1/llm_files` — create a new file at `directoryPath`
    /// with `title=name` and the supplied bytes attached as
    /// `llm_file[file]`. Multipart/form-data per the controller's
    /// `perform_file_create`. Returns the resulting FileDTO.
    ///
    /// Note on auto-rename: the controller auto-renames on collision at
    /// upload (e.g. `foo.md` → `foo (1).md`) — this is intentional per
    /// `LlmFilesController#perform_file_create` for the upload UX.
    /// Caller should use the FileDTO's `title` (not the requested name)
    /// when displaying the result.
    func createFile(directoryPath: String,
                    name: String,
                    bytes: Data,
                    contentType: String = "text/markdown")
        async throws -> FileDTO
    {
        var builder = MultipartFormDataBuilder()
        builder.appendFile(
            name: "llm_file[file]",
            filename: name,
            contentType: contentType,
            data: bytes)
        builder.appendText(name: "llm_file[directory_path]",
                           value: directoryPath)
        builder.appendText(name: "llm_file[title]", value: name)
        builder.finalize()

        let url = base("/llm_files")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        try setAuthHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(builder.contentType,
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = builder.body

        return try await sendForLlmFile(request)
    }

    /// `PATCH /api/v1/llm_files/:id` with `llm_file[title]=newName`.
    /// 422 on collision (Q5 — no auto-rename on rename).
    func renameFile(fileID: Int, newName: String) async throws -> FileDTO {
        try await patchLlmFile(
            fileID: fileID,
            jsonBody: ["llm_file": ["title": newName]])
    }

    /// `PATCH /api/v1/llm_files/:id` with `llm_file[directory_path]=newPath`.
    /// 422 on collision (server's pre-check guards against a sibling
    /// with the same title in `newPath`).
    func moveFile(fileID: Int,
                  newDirectoryPath: String) async throws -> FileDTO {
        try await patchLlmFile(
            fileID: fileID,
            jsonBody: ["llm_file": ["directory_path": newDirectoryPath]])
    }

    // MARK: - Internals — D23 helpers

    /// Common PATCH path for rename/move. JSON body (not multipart —
    /// we're not attaching a new file). Carries the same auth + tenant
    /// + status-code mapping as updateFile.
    private func patchLlmFile(fileID: Int,
                              jsonBody: [String: Any]) async throws -> FileDTO {
        let url = base("/llm_files/\(fileID)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        try setAuthHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: jsonBody, options: [])
        } catch {
            throw ConnectorError.network(error)
        }
        return try await sendForLlmFile(request)
    }

    /// Run `request` and decode the response as `LlmFileShowResponse`,
    /// mapping HTTP status codes to ConnectorError variants the way
    /// `updateFile` does. Shared between create / rename / move.
    private func sendForLlmFile(_ request: URLRequest) async throws -> FileDTO {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConnectorError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.network(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299:
            do {
                let resp = try JSONDecoder().decode(
                    LlmFileShowResponse.self, from: data)
                guard let file = resp.llm_file else {
                    throw ConnectorError.server(
                        status: http.statusCode,
                        message: "missing llm_file payload")
                }
                return file
            } catch {
                throw ConnectorError.server(
                    status: http.statusCode,
                    message: "decode failed: \(error)")
            }
        case 401, 403:
            let body = String(data: data, encoding: .utf8)
            throw ConnectorError.writeForbidden(
                body ?? "HTTP \(http.statusCode)")
        case 402:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ConnectorError.storageQuotaExceeded(body)
        default:
            // 422 (uniqueness collision) lands here as a `.server`
            // with the controller's error message — the modal layer
            // surfaces it inline. Could promote to a dedicated
            // `.nameConflict` case later if the UX wants tighter
            // typing.
            let body = String(data: data, encoding: .utf8)
            throw ConnectorError.server(
                status: http.statusCode, message: body)
        }
    }

    /// Set Bearer + X-Tenant-ID headers from the stored token. Throws
    /// `.unauthenticated` if no token is present. Shared between every
    /// authenticated endpoint.
    private func setAuthHeaders(_ request: inout URLRequest) throws {
        guard let token = try tokens.load(), !token.isEmpty else {
            throw ConnectorError.unauthenticated
        }
        request.setValue("Bearer \(token)",
                         forHTTPHeaderField: "Authorization")
        if let identifier = JWTPayload.tenantEnterpriseIdentifier(from: token) {
            request.setValue(identifier, forHTTPHeaderField: "X-Tenant-ID")
        }
    }

    // MARK: - Internals

    private func base(_ path: String) -> URL {
        // PortableMindEnvironment.baseURL ends without a trailing
        // slash; `path` starts with "/".
        URL(string: PortableMindEnvironment.baseURL.absoluteString + path)!
    }

    /// GET a JSON endpoint with bearer auth; decode into `T`.
    private func getJSON<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let token = try tokens.load(), !token.isEmpty else {
            throw ConnectorError.unauthenticated
        }
        request.setValue("Bearer \(token)",
                         forHTTPHeaderField: "Authorization")
        // Harmoniq's BaseController#set_tenant resolves the tenant
        // BEFORE validating the JWT — without an X-Tenant-ID header
        // (or a `tenant_id` query param), every call returns
        // `400 invalid tenant`. The JWT payload carries
        // `tenant_enterprise_identifier`; extract and forward it.
        if let identifier = JWTPayload.tenantEnterpriseIdentifier(from: token) {
            request.setValue(identifier, forHTTPHeaderField: "X-Tenant-ID")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConnectorError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.network(
                URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ConnectorError.server(
                    status: http.statusCode,
                    message: "decode failed: \(error)")
            }
        case 401, 403:
            throw ConnectorError.unauthenticated
        default:
            let body = String(data: data, encoding: .utf8)
            throw ConnectorError.server(
                status: http.statusCode, message: body)
        }
    }

    /// GET a signed ActiveStorage blob URL — no auth header (the URL
    /// already carries the signature). Module-internal so
    /// PortableMindConnector can drive open-time meta + blob fetches as
    /// two visible steps when it needs the meta's updated_at (D19 phase
    /// 4 conflict-detection baseline).
    func fetchSignedBlob(url: URL) async throws -> Data {
        let request = URLRequest(url: url)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConnectorError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ConnectorError.network(URLError(.badServerResponse))
        }
        if !(200...299).contains(http.statusCode) {
            throw ConnectorError.server(
                status: http.statusCode, message: nil)
        }
        return data
    }
}
