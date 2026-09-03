//
//  BackendCatalogService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

final class BackendCatalogService: BackendCatalogServiceProtocol {
    private let client: BackendAPIClient

    init(client: BackendAPIClient) {
        self.client = client
    }

    func items(
        mediaType: MediaType,
        filters: MediaFilters,
        query searchText: String,
        includeUnapproved: Bool,
        limit: Int,
        offset: Int
    ) async throws -> [CuratedItem] {
        struct Response: Decodable, Sendable {
            let items: [CuratedItem]
        }

        var query = BackendQuery.filters(mediaType: mediaType, filters: filters)
        if !searchText.isEmpty { query.append(URLQueryItem(name: "q", value: searchText)) }
        if includeUnapproved { query.append(URLQueryItem(name: "includeUnapproved", value: "true")) }
        query.append(URLQueryItem(name: "limit", value: "\(limit)"))
        query.append(URLQueryItem(name: "offset", value: "\(offset)"))

        let response: Response = try await client.get("/v1/catalog/items", query: query)
        return response.items
    }

    func count(mediaType: MediaType, filters: MediaFilters, excludeWatched: Bool) async throws -> CatalogCount {
        var query = BackendQuery.filters(mediaType: mediaType, filters: filters)
        query.append(URLQueryItem(name: "excludeWatched", value: excludeWatched ? "true" : "false"))
        return try await client.get("/v1/catalog/count", query: query)
    }

    func item(key: String) async throws -> CuratedItemDetail {
        try await client.get("/v1/catalog/items/\(key)")
    }

    func importTitles(mediaType: MediaType, tmdbIds: [Int]) async throws -> CatalogImportResult {
        struct Payload: Encodable, Sendable {
            let mediaType: MediaType
            let tmdbIds: [Int]
        }
        return try await client.post("/v1/catalog/import", body: Payload(mediaType: mediaType, tmdbIds: tmdbIds))
    }

    func importPopular(mediaType: MediaType, page: Int, limit: Int) async throws -> CatalogImportResult {
        struct Payload: Encodable, Sendable {
            let mediaType: MediaType
            let page: Int
            let limit: Int
        }
        return try await client.post("/v1/catalog/import-popular", body: Payload(mediaType: mediaType, page: page, limit: limit))
    }

    func curateTitle(key: String, verdicts: [FrameVerdict], rejectRemaining: Bool) async throws -> CuratedItem {
        struct Payload: Encodable, Sendable {
            let verdicts: [FrameVerdict]
            let rejectRemaining: Bool
        }
        struct Response: Decodable, Sendable {
            let item: CuratedItem
        }

        let response: Response = try await client.post(
            "/v1/catalog/items/\(key)/curate",
            body: Payload(verdicts: verdicts, rejectRemaining: rejectRemaining)
        )
        return response.item
    }

    func posterOptions(key: String) async throws -> [PosterOption] {
        struct Response: Decodable, Sendable {
            let posters: [PosterOption]
        }
        let response: Response = try await client.get("/v1/catalog/items/\(key)/posters")
        return response.posters
    }

    func setPoster(key: String, posterURL: String?) async throws -> CuratedItem {
        struct Payload: Encodable, Sendable {
            let posterURL: String?
        }
        return try await client.patch("/v1/catalog/items/\(key)", body: Payload(posterURL: posterURL))
    }

    func setFinalized(key: String, finalized: Bool) async throws -> CuratedItem {
        struct Payload: Encodable, Sendable {
            let adminFinalized: Bool
        }
        return try await client.patch("/v1/catalog/items/\(key)", body: Payload(adminFinalized: finalized))
    }
}
