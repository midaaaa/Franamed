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

    let tmdbClient: TMDBClientProtocol
    let firestoreService: FirestoreServiceProtocol

    init(tmdbClient: TMDBClientProtocol, firestoreService: FirestoreServiceProtocol) {
        self.tmdbClient = tmdbClient
        self.firestoreService = firestoreService
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

    func searchMedia(mediaType: MediaType, query: String, language: String) async throws -> [MediaItem] {
        try await tmdbClient.searchMedia(mediaType: mediaType, query: query, language: language)
    }

    func fetchGenres(mediaType: MediaType) async throws -> [Genre] {
        try await tmdbClient.fetchGenres(mediaType: mediaType)
    }

    func fetchResultsCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int {
        try await tmdbClient.fetchResultsCount(mediaType: mediaType, filters: filters)
    }
}
