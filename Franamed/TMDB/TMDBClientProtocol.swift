//
//  TMDBClientProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

protocol TMDBClientProtocol {
    func fetchRandomMediaItem(mediaType: MediaType, filters: MediaFilters) async throws -> MediaItem
    func fetchBackdrops(mediaType: MediaType, id: Int) async throws -> [Backdrop]
    func searchMedia(mediaType: MediaType, query: String, language: String) async throws -> [MediaItem]
    func fetchGenres(mediaType: MediaType) async throws -> [Genre]
    func fetchResultsCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int
}
