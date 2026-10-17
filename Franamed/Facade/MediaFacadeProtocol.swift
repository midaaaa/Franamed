//
//  MediaFacadeProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

protocol MediaFacadeProtocol {
    func fetchRandomMediaItemAndBackdrops(mediaType: MediaType, filters: MediaFilters, frameCount: Int) async throws -> MediaItemWithBackdrops
    func fetchRound(source: RoundSource, mediaType: MediaType, filters: MediaFilters, frameCount: Int, shuffle: ShuffleMode) async throws -> MediaItemWithBackdrops
    func searchMedia(mediaType: MediaType, query: String, language: String) async throws -> [MediaItem]
    func fetchGenres(mediaType: MediaType) async throws -> [Genre]
    func fetchDetails(mediaType: MediaType, id: Int) async throws -> MediaDetails
    func fetchResultsCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int

    func fetchPlaylistRound(playlistId: String, frameCount: Int) async throws -> MediaItemWithBackdrops
    func finishRound(mediaType: MediaType, tmdbId: Int, frameCount: Int, solvedAtFrame: Int?, playlistId: String?) async -> RoundStats?
    func resetPlayedTitles() async throws
    func fetchCuratedCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int
}
