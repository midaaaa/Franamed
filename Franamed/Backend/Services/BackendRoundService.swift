//
//  BackendRoundService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

final class BackendRoundService: BackendRoundServiceProtocol {
    private let client: BackendAPIClient

    init(client: BackendAPIClient) {
        self.client = client
    }

    func curatedRound(mediaKey: String, frameCount: Int) async throws -> RoundPayload {
        try await client.get("/v1/round/next", query: [
            URLQueryItem(name: "pool", value: RoundPool.curated.rawValue),
            URLQueryItem(name: "mediaKey", value: mediaKey),
            URLQueryItem(name: "frameCount", value: "\(frameCount)")
        ])
    }

    func nextPlaylistRound(
        playlistId: String,
        pick: PlaylistPickMode,
        mediaKey: String?,
        frameCount: Int
    ) async throws -> RoundPayload {
        var query = [
            URLQueryItem(name: "pool", value: RoundPool.playlist.rawValue),
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "pick", value: pick.rawValue),
            URLQueryItem(name: "frameCount", value: "\(frameCount)")
        ]
        if let mediaKey { query.append(URLQueryItem(name: "mediaKey", value: mediaKey)) }

        return try await client.get("/v1/round/next", query: query)
    }

    func dailyRound(date: String?, frameCount: Int) async throws -> RoundPayload {
        var query = [
            URLQueryItem(name: "pool", value: RoundPool.daily.rawValue),
            URLQueryItem(name: "frameCount", value: "\(frameCount)")
        ]
        if let date { query.append(URLQueryItem(name: "date", value: date)) }

        return try await client.get("/v1/round/next", query: query)
    }
}
