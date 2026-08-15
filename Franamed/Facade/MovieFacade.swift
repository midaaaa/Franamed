//
//  MovieFacade.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

final class MovieFacade: MovieFacadeProtocol {
    let tmdbClient: TMDBClientProtocol
    let firestoreService: FirestoreServiceProtocol

    init(tmdbClient: TMDBClientProtocol, firestoreService: FirestoreServiceProtocol) {
        self.tmdbClient = tmdbClient
        self.firestoreService = firestoreService
    }

    func fetchRandomMovieAndBackdrops(filters: MovieFilters) async throws -> MovieWithBackdrops {
        let movie = try await tmdbClient.fetchRandomMovie(filters: filters)
        let backdrops = try await tmdbClient.fetchMovieBackdrops(movieID: movie.id)

        return MovieWithBackdrops(movie: movie, backdrops: backdrops)
    }

    func searchMovies(query: String, language: String) async throws -> [Movie] {
        try await tmdbClient.searchMovies(query: query, language: language)
    }
}
