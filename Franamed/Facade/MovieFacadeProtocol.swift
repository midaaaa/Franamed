//
//  MovieFacadeProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

protocol MovieFacadeProtocol {
    func fetchRandomMovieAndBackdrops(filters: MovieFilters) async throws -> MovieWithBackdrops
    func searchMovies(query: String, language: String) async throws -> [Movie]
}
