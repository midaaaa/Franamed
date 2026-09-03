//
//  BackendCatalogServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendCatalogServiceProtocol: Sendable {
    func items(mediaType: MediaType, filters: MediaFilters, query: String, includeUnapproved: Bool, limit: Int, offset: Int) async throws -> [CuratedItem]

    func count(mediaType: MediaType, filters: MediaFilters, excludeWatched: Bool) async throws -> CatalogCount

    func item(key: String) async throws -> CuratedItemDetail

    func importTitles(mediaType: MediaType, tmdbIds: [Int]) async throws -> CatalogImportResult
    func importPopular(mediaType: MediaType, page: Int, limit: Int) async throws -> CatalogImportResult

    func curateTitle(key: String, verdicts: [FrameVerdict], rejectRemaining: Bool) async throws -> CuratedItem

    func posterOptions(key: String) async throws -> [PosterOption]
    func setPoster(key: String, posterURL: String?) async throws -> CuratedItem
    func setFinalized(key: String, finalized: Bool) async throws -> CuratedItem
}

extension BackendCatalogServiceProtocol {
    func items(
        mediaType: MediaType,
        filters: MediaFilters,
        query searchText: String = "",
        includeUnapproved: Bool = false
    ) async throws -> [CuratedItem] {
        try await items(
            mediaType: mediaType,
            filters: filters,
            query: searchText,
            includeUnapproved: includeUnapproved,
            limit: 50,
            offset: 0
        )
    }
}
