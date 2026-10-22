//
//  MediaFacade.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

final class MediaFacade: MediaFacadeProtocol {
    private static let minAvailableBackdrops = 6
    private static let maxSelectionAttempts = 8
    private static let maxStaleIndexRetries = 2

    let tmdbClient: TMDBClientProtocol
    let backend: Backend

    init(tmdbClient: TMDBClientProtocol, backend: Backend) {
        self.tmdbClient = tmdbClient
        self.backend = backend
    }

    func fetchRandomMediaItemAndBackdrops(mediaType: MediaType, filters: MediaFilters, frameCount: Int) async throws -> MediaItemWithBackdrops {
        for _ in 0..<Self.maxSelectionAttempts {
            let item = try await tmdbClient.fetchRandomMediaItem(mediaType: mediaType, filters: filters)
            let backdrops = try await tmdbClient.fetchBackdrops(mediaType: mediaType, id: item.id)
            if backdrops.count >= Self.minAvailableBackdrops {
                return MediaItemWithBackdrops(item: item, backdrops: Array(backdrops.prefix(frameCount)))
            }
        }

        throw TMDBError.noSuitableMovieFound
    }

    func fetchRound(source: RoundSource, mediaType: MediaType, filters: MediaFilters, frameCount: Int, shuffle: ShuffleMode) async throws -> MediaItemWithBackdrops {
        switch source {
        case .tmdb:
            return try await fetchRandomMediaItemAndBackdrops(mediaType: mediaType, filters: filters, frameCount: frameCount)
        case .curated:
            let payload = try await fetchCuratedRound(mediaType: mediaType, filters: filters, frameCount: frameCount, shuffle: shuffle)
            return payload.asMediaItemWithBackdrops(imageBaseURL: backend.configuration.imageBaseURL)
        }
    }

    func searchMedia(mediaType: MediaType, query: String, language: String) async throws -> [MediaItem] {
        try await tmdbClient.searchMedia(mediaType: mediaType, query: query, language: language)
    }

    func fetchGenres(mediaType: MediaType) async throws -> [Genre] {
        try await tmdbClient.fetchGenres(mediaType: mediaType)
    }

    func fetchDetails(mediaType: MediaType, id: Int) async throws -> MediaDetails {
        try await tmdbClient.fetchDetails(mediaType: mediaType, id: id)
    }

    func fetchResultsCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int {
        try await tmdbClient.fetchResultsCount(mediaType: mediaType, filters: filters)
    }

    private func fetchCuratedRound(mediaType: MediaType, filters: MediaFilters, frameCount: Int, shuffle: ShuffleMode) async throws -> RoundPayload {
        var index = try await backend.catalogIndex.current()
        Task { [playedTitles = backend.playedTitles] in await playedTitles.sendPending() }
        let played = await backend.playedTitles.all()
        for _ in 0...Self.maxStaleIndexRetries {
            let entries = index.entries(mediaType: mediaType, filters: filters)
            guard let entry = CuratedPicker.pick(from: entries, played: played, shuffle: shuffle) else {
                throw CuratedRoundError.noMatches
            }
            do {
                return try await backend.round.curatedRound(mediaKey: entry.key, frameCount: frameCount)
            } catch let error as BackendError where error.isNotPlayable {
                index = try await backend.catalogIndex.refresh()
            }
        }
        throw CuratedRoundError.noMatches
    }

    func fetchPlaylistRound(playlistId: String, frameCount: Int) async throws -> MediaItemWithBackdrops {
        Task { [playedTitles = backend.playedTitles] in await playedTitles.sendPending() }
        let payload = try await backend.round.nextPlaylistRound(playlistId: playlistId, pick: .shuffle, mediaKey: nil, frameCount: frameCount)
        return payload.asMediaItemWithBackdrops(imageBaseURL: backend.configuration.imageBaseURL)
    }

    func fetchPlaylistEntry(playlistId: String, mediaKey: String, frameCount: Int) async throws -> MediaItemWithBackdrops {
        let payload = try await backend.round.nextPlaylistRound(playlistId: playlistId, pick: .next, mediaKey: mediaKey, frameCount: frameCount)
        return payload.asMediaItemWithBackdrops(imageBaseURL: backend.configuration.imageBaseURL)
    }

    func finishRound(mediaType: MediaType, tmdbId: Int, frameCount: Int, solvedAtFrame: Int?, playlistId: String?) async -> RoundStats? {
        let mediaKey = "\(mediaType.rawValue)_\(tmdbId)"
        let playedAt = Date.now
        if let playlistId {
            await backend.playlistsStore.record(playlistId: playlistId, mediaKey: mediaKey, attemptsUsed: solvedAtFrame ?? frameCount,
                                                wasCorrect: solvedAtFrame != nil, at: playedAt)
        }
        let finish = await backend.playedTitles.record(PendingFinish(
            mediaKey: mediaKey,
            frameCount: frameCount,
            solvedAtFrame: solvedAtFrame,
            playedAt: playedAt,
            playlistId: playlistId
        ))
        return finish?.stats.map { RoundStats(players: $0.players, solvedAtFrame: $0.solvedAtFrame) }
    }

    func resetPlayedTitles() async throws {
        try await backend.playedTitles.reset()
    }

    func fetchCuratedCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int {
        try await backend.catalogIndex.current().entries(mediaType: mediaType, filters: filters).count
    }
}
