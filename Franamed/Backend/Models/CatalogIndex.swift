//
//  CatalogIndex.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

struct CatalogIndex: Codable, Sendable {
    let version: String
    let items: [Entry]

    struct Entry: Codable, Sendable {
        let key: String
        let type: MediaType
        let year: Int?
        let language: String?
        let genres: [Int]
        let rating: Double
        let votes: Int
    }

    func entries(mediaType: MediaType, filters: MediaFilters) -> [Entry] {
        items.filter { $0.type == mediaType && $0.matches(filters) }
    }
}

extension CatalogIndex.Entry {
    func matches(_ filters: MediaFilters) -> Bool {
        if let wanted = filters.genres, !wanted.isEmpty, Set(wanted).isDisjoint(with: genres) {
            return false
        }
        if let range = filters.yearRange {
            guard let year, range.contains(year) else { return false }
        }
        if let languages = filters.originalLanguages, !languages.isEmpty {
            guard let language, languages.contains(language) else { return false }
        }
        if let minRating = filters.minRating, rating < minRating {
            return false
        }
        if let minVoteCount = filters.minVoteCount, votes < minVoteCount {
            return false
        }
        return true
    }
}
