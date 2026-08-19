//
//  TMDBClientProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

protocol TMDBClientProtocol {
    func fetchRandomMovie(filters: MovieFilters) async throws -> Movie
    func fetchMovieBackdrops(movieID: Int) async throws -> [Backdrop]
    func searchMovies(query: String, language: String) async throws -> [Movie]
    func fetchGenres() async throws -> [Genre]
    func fetchResultsCount(filters: MovieFilters) async throws -> Int
}
