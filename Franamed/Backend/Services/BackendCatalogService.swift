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

    func index(ifNoneMatch version: String?) async throws -> CatalogIndex? {
        try await client.get("/v1/catalog/index", ifNoneMatch: version)
    }

    func item(key: String) async throws -> CuratedItemDetail {
        try await client.get("/v1/catalog/items/\(key)")
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
}
