//
//  MediaFacadeProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

protocol MediaFacadeProtocol {
    func fetchRandomMediaItemAndBackdrops(mediaType: MediaType, filters: MediaFilters, frameCount: Int) async throws -> MediaItemWithBackdrops
    func searchMedia(mediaType: MediaType, query: String, language: String) async throws -> [MediaItem]
    func fetchGenres(mediaType: MediaType) async throws -> [Genre]
    func fetchResultsCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int

    func fetchCuratedRound(mediaType: MediaType, filters: MediaFilters, frameCount: Int, excludeWatched: Bool) async throws -> RoundPayload
    func fetchCuratedCount(mediaType: MediaType, filters: MediaFilters, excludeWatched: Bool) async throws -> Int
}
