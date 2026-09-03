//
//  BackendAdminService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

final class BackendAdminService: BackendAdminServiceProtocol {
    private let client: BackendAPIClient

    init(client: BackendAPIClient) {
        self.client = client
    }

    func config() async throws -> AppGameConfig {
        try await client.get("/v1/admin/config")
    }

    func updateConfig(_ updates: [String: String]) async throws -> AppGameConfig {
        try await client.patch("/v1/admin/config", body: updates)
    }

    func users() async throws -> [AdminUserSummary] {
        struct Response: Decodable, Sendable {
            let users: [AdminUserSummary]
        }
        let response: Response = try await client.get("/v1/admin/users")
        return response.users
    }

    func setRole(uid: String, role: UserRole) async throws {
        struct Payload: Encodable, Sendable {
            let uid: String
            let role: UserRole
        }
        struct Response: Decodable, Sendable {
            let uid: String
        }

        let _: Response = try await client.post("/v1/admin/roles", body: Payload(uid: uid, role: role))
    }

    func dailySchedule() async throws -> [ScheduledDaily] {
        struct Response: Decodable, Sendable {
            let schedule: [ScheduledDaily]
        }
        let response: Response = try await client.get("/v1/admin/daily")
        return response.schedule
    }

    func scheduleDaily(date: String, mediaKey: String) async throws {
        struct Payload: Encodable, Sendable {
            let mediaKey: String
        }
        struct Response: Decodable, Sendable {
            let date: String
        }

        let _: Response = try await client.put("/v1/admin/daily/\(date)", body: Payload(mediaKey: mediaKey))
    }

    func stats() async throws -> CatalogStats {
        try await client.get("/v1/admin/stats")
    }
}
