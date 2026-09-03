//
//  BackendRoundServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendRoundServiceProtocol: Sendable {
    func nextCuratedRound(
        mediaType: MediaType,
        filters: MediaFilters,
        frameCount: Int,
        excludeWatched: Bool
    ) async throws -> RoundPayload

    func nextPlaylistRound(
        playlistId: String,
        pick: PlaylistPickMode,
        mediaKey: String?,
        frameCount: Int
    ) async throws -> RoundPayload

    func dailyRound(date: String?, frameCount: Int) async throws -> RoundPayload
}

extension BackendRoundServiceProtocol {
    func nextPlaylistRound(
        playlistId: String,
        pick: PlaylistPickMode = .next,
        mediaKey: String? = nil
    ) async throws -> RoundPayload {
        try await nextPlaylistRound(playlistId: playlistId, pick: pick, mediaKey: mediaKey, frameCount: 6)
    }
}
