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
            URLQueryItem(name: "language", value: "ru-RU"),
            URLQueryItem(name: "include_adult", value: String(filters.includeAdult)),
            URLQueryItem(name: "sort_by", value: filters.sortBy.rawValue)
        ]

        if let genres = filters.genres, !genres.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "with_genres", value: genres.map(String.init).joined(separator: "|")))
        }

        if let yearRange = filters.yearRange {
            components.queryItems?.append(URLQueryItem(name: "primary_release_date.gte", value: "\(yearRange.lowerBound)-01-01"))
            components.queryItems?.append(URLQueryItem(name: "primary_release_date.lte", value: "\(yearRange.upperBound)-12-31"))
        }

        if let minRating = filters.minRating {
            components.queryItems?.append(URLQueryItem(name: "vote_average.gte", value: String(minRating)))
        }

        if let minVoteCount = filters.minVoteCount {
            components.queryItems?.append(URLQueryItem(name: "vote_count.gte", value: String(minVoteCount)))
        }

        if let originalLanguages = filters.originalLanguages, !originalLanguages.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "with_original_language", value: originalLanguages.joined(separator: "|")))
        }

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
        return backdropsResponse.backdrops
            .filter { $0.iso6391 == nil }
            .map { rawBackdrop in
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

    func fetchResultsCount(filters: MovieFilters) async throws -> Int {
        let response = try await discoverMovies(page: 1, filters: filters)
        return response.totalResults
    }

    func fetchGenres() async throws -> [Genre] {
        guard var components = URLComponents(string: "\(baseURL)/3/genre/movie/list") else {
            throw TMDBError.invalidResponse
        }

        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"

        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "language", value: languageCode)
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

        let genresResponse = try decoder.decode(GenresResponse.self, from: data)
        return genresResponse.genres
    }
}

enum TMDBError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyResults
    case noSuitableMovieFound
}

private struct MoviesListResponse: Decodable {
    let results: [Movie]
    let totalPages: Int
    let totalResults: Int
}

private struct MovieBackdropsResponse: Decodable {
    let backdrops: [TMDBBackdropDTO]
}

private struct TMDBBackdropDTO: Decodable {
    let filePath: String
    let iso6391: String?
}

private struct GenresResponse: Decodable {
    let genres: [Genre]
}
