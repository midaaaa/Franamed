//
//  MovieFacadeProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

protocol MovieFacadeProtocol {
    func fetchRandomMovieAndBackdrops(filters: MovieFilters, frameCount: Int) async throws -> MovieWithBackdrops
    func searchMovies(query: String, language: String) async throws -> [Movie]
    func fetchGenres() async throws -> [Genre]
    func fetchResultsCount(filters: MovieFilters) async throws -> Int
}
