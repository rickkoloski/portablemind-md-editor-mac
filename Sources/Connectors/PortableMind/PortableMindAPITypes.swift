// D18 phase 2 — Codable DTOs mirroring Harmoniq REST responses.
//
// Responses follow the envelope `{success: bool, ...}` with the data
// payload alongside (e.g. `llm_directories: [...]`, `user: {...}`,
// `llm_file: {...}`). DTO names mirror the Rails model names.

import Foundation

// MARK: - Envelopes

struct ListDirectoriesResponse: Decodable {
    let success: Bool
    let total_count: Int?
    let llm_directories: [DirectoryDTO]?
}

struct ListFilesResponse: Decodable {
    let success: Bool
    let total_count: Int?
    let llm_files: [FileDTO]?
}

struct CurrentUserResponse: Decodable {
    let success: Bool
    let user: CurrentUserDTO?
}

struct LlmFileShowResponse: Decodable {
    let success: Bool
    let llm_file: FileDTO?
}

// MARK: - Entities

struct DirectoryDTO: Decodable {
    let id: Int
    let name: String
    let path: String
    let parent_path: String?
    let depth: Int?
    let file_count: Int?
    let subdirectory_count: Int?
    let tenant_id: Int
    let tenant_enterprise_identifier: String?
    let tenant_name: String?
}

struct FileDTO: Decodable {
    let id: Int
    let title: String
    let type: String?              // STI: "LlmDocument" | "LlmImage" | …
    let directory_path: String?
    let full_path: String?
    let url: String?               // Signed ActiveStorage blob URL (1h)
    let `private`: Bool?
    let owner_party_id: Int?
    let tenant_id: Int
    let tenant_enterprise_identifier: String?
    let tenant_name: String?
    /// Server-side modification time (ISO8601). Used by D19 phase 3+
    /// for `lastSeenUpdatedAt` plumbing and phase 4's conflict prompt.
    let updated_at: String?
}

struct CurrentUserDTO: Decodable {
    let id: Int
    let tenant_id: Int
    let username: String?
    let email: String?
    let party_id: Int?
    let display_name: String?
    let tenant_enterprise_identifier: String?
    let tenant_name: String?
}
