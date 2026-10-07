//
//  BackendProfileService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

final class BackendProfileService: BackendProfileServiceProtocol {
    private let client: BackendAPIClient

    init(client: BackendAPIClient) {
        self.client = client
    }

    func profile() async throws -> BackendUser {
        struct Response: Decodable, Sendable {
            let user: BackendUser
        }
        let response: Response = try await client.get("/v1/profile")
        return response.user
    }

    func setStatsExcluded(_ excluded: Bool) async throws -> BackendUser {
        struct Payload: Encodable, Sendable {
            let statsExcluded: Bool
        }
        struct Response: Decodable, Sendable {
            let user: BackendUser
        }
        let response: Response = try await client.patch("/v1/profile", body: Payload(statsExcluded: excluded))
        return response.user
    }

    func watched(since: Double) async throws -> [WatchedEntry] {
        struct Response: Decodable, Sendable {
            let watched: [WatchedEntry]
        }
        let response: Response = try await client.get("/v1/profile/watched", query: [
            URLQueryItem(name: "since", value: "\(Int(since))")
        ])
        return response.watched
    }

    func syncWatched(_ entries: [WatchedEntry]) async throws -> Int {
        struct Payload: Encodable, Sendable {
            let items: [WatchedEntry]
        }
        struct Response: Decodable, Sendable {
            let synced: Int
        }

        let response: Response = try await client.post("/v1/profile/watched", body: Payload(items: entries))
        return response.synced
    }

    func resetWatched(source: WatchedSource?) async throws {
        let query = source.map { [URLQueryItem(name: "source", value: $0.rawValue)] } ?? []
        try await client.delete("/v1/profile/watched", query: query)
    }

    func dailyStatus() async throws -> DailyStatus {
        try await client.get("/v1/profile/daily")
    }
}
