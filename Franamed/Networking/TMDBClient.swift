//
//  TMDBClient.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

enum TMDBError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyResults
}

final class TMDBClient: TMDBClientProtocol {
    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    private static let maxPage = 500

    func fetchRandomMovie(filters: MovieFilters) async throws -> Movie {
        let firstPage = try await discoverMovies(page: 1, filters: filters)

        guard firstPage.totalPages > 0 else {
            throw TMDBError.emptyResults
        }

        let upperBound = min(firstPage.totalPages, Self.maxPage)
        let randomPage = Int.random(in: 1...upperBound)

        let page = randomPage == 1
            ? firstPage
            : try await discoverMovies(page: randomPage, filters: filters)

        guard let randomMovie = page.results.randomElement() else {
            throw TMDBError.emptyResults
        }
        return randomMovie
    }

    private func discoverMovies(page: Int, filters: MovieFilters) async throws -> DiscoverMovieResponse {
        let url = discoverURL(page: page, filters: filters)

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TMDBError.httpError(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(DiscoverMovieResponse.self, from: data)
    }

    private func discoverURL(page: Int, filters: MovieFilters) -> URL {
        var components = URLComponents(string: "https://api.themoviedb.org/3/discover/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "page", value: String(page))
        ]
        // filters пока пустые (MovieFilters — заглушка), доп. queryItems добавятся здесь на Этапе 3
        return components.url!
    }
}

private struct DiscoverMovieResponse: Decodable {
    let results: [Movie]
    let totalPages: Int
}
