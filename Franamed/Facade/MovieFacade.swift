//
//  MovieFacade.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

final class MovieFacade: MovieFacadeProtocol {
    private static let minAvailableBackdrops = 6
    private static let maxSelectionAttempts = 8

    let tmdbClient: TMDBClientProtocol
    let firestoreService: FirestoreServiceProtocol

    init(tmdbClient: TMDBClientProtocol, firestoreService: FirestoreServiceProtocol) {
        self.tmdbClient = tmdbClient
        self.firestoreService = firestoreService
    }

    func fetchRandomMovieAndBackdrops(filters: MovieFilters, frameCount: Int) async throws -> MovieWithBackdrops {
        for _ in 0..<Self.maxSelectionAttempts {
            let movie = try await tmdbClient.fetchRandomMovie(filters: filters)
            let backdrops = try await tmdbClient.fetchMovieBackdrops(movieID: movie.id)
            if backdrops.count >= Self.minAvailableBackdrops {
                return MovieWithBackdrops(movie: movie, backdrops: Array(backdrops.prefix(frameCount)))
            }
        }

        throw TMDBError.noSuitableMovieFound
    }

    func searchMovies(query: String, language: String) async throws -> [Movie] {
        try await tmdbClient.searchMovies(query: query, language: language)
    }

    func fetchGenres() async throws -> [Genre] {
        try await tmdbClient.fetchGenres()
    }

    func fetchResultsCount(filters: MovieFilters) async throws -> Int {
        try await tmdbClient.fetchResultsCount(filters: filters)
    }
}
