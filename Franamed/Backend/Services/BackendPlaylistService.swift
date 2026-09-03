//
//  BackendPlaylistService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

final class BackendPlaylistService: BackendPlaylistServiceProtocol {
    private let client: BackendAPIClient

    init(client: BackendAPIClient) {
        self.client = client
    }

    func playlists(mediaType: MediaType?, includeUnpublished: Bool) async throws -> [Playlist] {
        struct Response: Decodable, Sendable {
            let playlists: [Playlist]
        }

        var query: [URLQueryItem] = []
        if let mediaType { query.append(URLQueryItem(name: "mediaType", value: mediaType.rawValue)) }
        if includeUnpublished { query.append(URLQueryItem(name: "includeUnpublished", value: "true")) }

        let response: Response = try await client.get("/v1/playlists", query: query)
        return response.playlists
    }

    func playlist(id: String) async throws -> PlaylistDetail {
        try await client.get("/v1/playlists/\(id)")
    }

    func create(title: String, description: String?, mediaType: MediaType) async throws -> Playlist {
        struct Payload: Encodable, Sendable {
            let title: String
            let description: String?
            let mediaType: MediaType
        }
        return try await client.post("/v1/playlists", body: Payload(title: title, description: description, mediaType: mediaType))
    }

    func setPublished(id: String, published: Bool) async throws -> Playlist {
        struct Payload: Encodable, Sendable {
            let published: Bool
        }
        return try await client.patch("/v1/playlists/\(id)", body: Payload(published: published))
    }

    func setItems(id: String, mediaKeys: [String]) async throws {
        struct Payload: Encodable, Sendable {
            let mediaKeys: [String]
        }
        struct Response: Decodable, Sendable {
            let count: Int
        }

        let _: Response = try await client.put("/v1/playlists/\(id)/items", body: Payload(mediaKeys: mediaKeys))
    }

    func recordProgress(id: String, mediaKey: String, attemptsUsed: Int, wasCorrect: Bool) async throws -> PlaylistProgress {
        struct Payload: Encodable, Sendable {
            let mediaKey: String
            let attemptsUsed: Int
            let wasCorrect: Bool
        }
        struct Response: Decodable, Sendable {
            let progress: PlaylistProgress
            let awardedAttempts: Int
        }

        let response: Response = try await client.post(
            "/v1/playlists/\(id)/progress",
            body: Payload(mediaKey: mediaKey, attemptsUsed: attemptsUsed, wasCorrect: wasCorrect)
        )
        return response.progress
    }

    func reset(id: String, mode: PlaylistResetMode) async throws -> PlaylistProgress {
        struct Payload: Encodable, Sendable {
            let mode: PlaylistResetMode
        }
        struct Response: Decodable, Sendable {
            let progress: PlaylistProgress
        }

        let response: Response = try await client.post("/v1/playlists/\(id)/reset", body: Payload(mode: mode))
        return response.progress
    }
}
