//
//  TMDBClient.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

final class TMDBClient: TMDBClientProtocol {
    private static let defaultBaseURL = "https://franamed-tmdb-proxy.fildima8423.workers.dev"

    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(apiKey: String, baseURL: String = TMDBClient.defaultBaseURL, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    private func discoverURL(page: Int, filters: MovieFilters) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/3/discover/movie") else {
            throw TMDBError.invalidResponse
        }

        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "language", value: "ru-RU")
        ]

        guard let url = components.url else {
            throw TMDBError.invalidResponse
        }
        return url
    }

    private func discoverMovies(page: Int, filters: MovieFilters) async throws -> MoviesListResponse {
        let url = try discoverURL(page: page, filters: filters)
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TMDBError.httpError(statusCode: httpResponse.statusCode)
        }

        let movies = try decoder.decode(MoviesListResponse.self, from: data)
        return movies
    }

    func fetchRandomMovie(filters: MovieFilters) async throws -> Movie {
        let moviesFirstPage = try await discoverMovies(page: 1, filters: filters)

        guard moviesFirstPage.totalPages > 0 else {
            throw TMDBError.emptyResults
        }

        let randomPage = Int.random(in: 1...min(moviesFirstPage.totalPages, 500))

        let movies = randomPage == 1 ? moviesFirstPage : try await discoverMovies(page: randomPage, filters: filters)

        guard !movies.results.isEmpty, let movie = movies.results.randomElement() else {
            throw TMDBError.emptyResults
        }
        return movie
    }

    func fetchMovieBackdrops(movieID: Int) async throws -> [Backdrop] {
        guard var components = URLComponents(string: "\(baseURL)/3/movie/\(movieID)/images") else {
            throw TMDBError.invalidResponse
        }

        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        guard let url = components.url else {
            throw TMDBError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TMDBError.httpError(statusCode: httpResponse.statusCode)
        }

        let backdropsResponse = try decoder.decode(MovieBackdropsResponse.self, from: data)
        return backdropsResponse.backdrops.map { rawBackdrop in
            Backdrop(filePath: "\(baseURL)/t/p/w1280\(rawBackdrop.filePath)")
        }
    }

    func searchMovies(query: String, language: String) async throws -> [Movie] {
        guard var components = URLComponents(string: "\(baseURL)/3/search/movie") else {
            throw TMDBError.invalidResponse
        }

        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: language)
        ]

        guard let url = components.url else {
            throw TMDBError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TMDBError.httpError(statusCode: httpResponse.statusCode)
        }

        let movies = try decoder.decode(MoviesListResponse.self, from: data)
        return movies.results
    }
}

enum TMDBError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyResults
}

private struct MoviesListResponse: Decodable {
    let results: [Movie]
    let totalPages: Int
}

private struct MovieBackdropsResponse: Decodable {
    let backdrops: [TMDBBackdropDTO]
}

private struct TMDBBackdropDTO: Decodable {
    let filePath: String
}
