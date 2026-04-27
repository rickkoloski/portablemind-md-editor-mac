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
    /// already carries the signature).
    private func fetchSignedBlob(url: URL) async throws -> Data {
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
