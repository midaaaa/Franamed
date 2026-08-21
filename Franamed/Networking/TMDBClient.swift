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

    private func dateFilterParam(for mediaType: MediaType) -> String {
        switch mediaType {
        case .movie: return "primary_release_date"
        case .tv: return "first_air_date"
        }
    }

    private func discoverURL(mediaType: MediaType, page: Int, filters: MediaFilters) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/3/discover/\(mediaType.rawValue)") else {
            throw TMDBError.invalidResponse
        }

        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "language", value: "ru-RU"),
            URLQueryItem(name: "include_adult", value: String(filters.includeAdult)),
            URLQueryItem(name: "sort_by", value: filters.sortBy.tmdbValue(for: mediaType))
        ]

        if let genres = filters.genres, !genres.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "with_genres", value: genres.map(String.init).joined(separator: "|")))
        }

        if let yearRange = filters.yearRange {
            let param = dateFilterParam(for: mediaType)
            components.queryItems?.append(URLQueryItem(name: "\(param).gte", value: "\(yearRange.lowerBound)-01-01"))
            components.queryItems?.append(URLQueryItem(name: "\(param).lte", value: "\(yearRange.upperBound)-12-31"))
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

    private func discoverMedia(mediaType: MediaType, page: Int, filters: MediaFilters) async throws -> MediaListResponse {
        let url = try discoverURL(mediaType: mediaType, page: page, filters: filters)
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TMDBError.httpError(statusCode: httpResponse.statusCode)
        }

        return try decodeList(mediaType: mediaType, data: data)
    }

    func fetchRandomMediaItem(mediaType: MediaType, filters: MediaFilters) async throws -> MediaItem {
        let firstPage = try await discoverMedia(mediaType: mediaType, page: 1, filters: filters)

        guard firstPage.totalPages > 0 else {
            throw TMDBError.emptyResults
        }

        let randomPage = Int.random(in: 1...min(firstPage.totalPages, 500))

        let page = randomPage == 1 ? firstPage : try await discoverMedia(mediaType: mediaType, page: randomPage, filters: filters)

        guard !page.results.isEmpty, let item = page.results.randomElement() else {
            throw TMDBError.emptyResults
        }
        return item
    }

    func fetchBackdrops(mediaType: MediaType, id: Int) async throws -> [Backdrop] {
        guard var components = URLComponents(string: "\(baseURL)/3/\(mediaType.rawValue)/\(id)/images") else {
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

        let backdropsResponse = try decoder.decode(BackdropsResponse.self, from: data)
        return backdropsResponse.backdrops
            .filter { $0.iso6391 == nil }
            .map { rawBackdrop in
                Backdrop(filePath: "\(baseURL)/t/p/w1280\(rawBackdrop.filePath)")
            }
    }

    func searchMedia(mediaType: MediaType, query: String, language: String) async throws -> [MediaItem] {
        guard var components = URLComponents(string: "\(baseURL)/3/search/\(mediaType.rawValue)") else {
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

        return try decodeList(mediaType: mediaType, data: data).results
    }

    func fetchResultsCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int {
        let response = try await discoverMedia(mediaType: mediaType, page: 1, filters: filters)
        return response.totalResults
    }

    func fetchGenres(mediaType: MediaType) async throws -> [Genre] {
        guard var components = URLComponents(string: "\(baseURL)/3/genre/\(mediaType.rawValue)/list") else {
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

    private func decodeList(mediaType: MediaType, data: Data) throws -> MediaListResponse {
        switch mediaType {
        case .movie:
            let response = try decoder.decode(MovieListResponse.self, from: data)
            return MediaListResponse(
                results: response.results.map { $0.asMediaItem() },
                totalPages: response.totalPages,
                totalResults: response.totalResults
            )
        case .tv:
            let response = try decoder.decode(TVListResponse.self, from: data)
            return MediaListResponse(
                results: response.results.map { $0.asMediaItem() },
                totalPages: response.totalPages,
                totalResults: response.totalResults
            )
        }
    }
}

enum TMDBError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyResults
    case noSuitableMovieFound
}

private struct MediaListResponse {
    let results: [MediaItem]
    let totalPages: Int
    let totalResults: Int
}

private struct MovieListResponse: Decodable {
    let results: [MovieDTO]
    let totalPages: Int
    let totalResults: Int
}

private struct TVListResponse: Decodable {
    let results: [TVDTO]
    let totalPages: Int
    let totalResults: Int
}

private struct MovieDTO: Decodable {
    let id: Int
    let title: String
    let originalTitle: String
    let releaseDate: String?
    let overview: String?

    func asMediaItem() -> MediaItem {
        MediaItem(id: id, mediaType: .movie, title: title, originalTitle: originalTitle, releaseDate: releaseDate, overview: overview)
    }
}

private struct TVDTO: Decodable {
    let id: Int
    let name: String
    let originalName: String
    let firstAirDate: String?
    let overview: String?

    func asMediaItem() -> MediaItem {
        MediaItem(id: id, mediaType: .tv, title: name, originalTitle: originalName, releaseDate: firstAirDate, overview: overview)
    }
}

private struct BackdropsResponse: Decodable {
    let backdrops: [TMDBBackdropDTO]
}

private struct TMDBBackdropDTO: Decodable {
    let filePath: String
    let iso6391: String?
}

private struct GenresResponse: Decodable {
    let genres: [Genre]
}
