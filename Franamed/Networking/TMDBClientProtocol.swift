//
//  TMDBClientProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

protocol TMDBClientProtocol {
    func fetchRandomMovie(filters: MovieFilters) async throws -> Movie
}
