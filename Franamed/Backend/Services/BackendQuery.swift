//
//  BackendQuery.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum BackendQuery {
    static func filters(mediaType: MediaType, filters: MediaFilters) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "mediaType", value: mediaType.rawValue)]

        if let genres = filters.genres, !genres.isEmpty {
            items.append(URLQueryItem(name: "genres", value: genres.map(String.init).joined(separator: ",")))
        }
        if let yearRange = filters.yearRange {
            items.append(URLQueryItem(name: "yearFrom", value: "\(yearRange.lowerBound)"))
            items.append(URLQueryItem(name: "yearTo", value: "\(yearRange.upperBound)"))
        }
        if let languages = filters.originalLanguages, !languages.isEmpty {
            items.append(URLQueryItem(name: "languages", value: languages.joined(separator: ",")))
        }

        return items
    }

    static func unsupportedByCuratedPool(_ filters: MediaFilters) -> [String] {
        var unsupported: [String] = []
        if filters.minRating != nil { unsupported.append("минимальный рейтинг") }
        if filters.minVoteCount != nil { unsupported.append("число оценок") }
        if filters.sortBy != .popularityDesc { unsupported.append("сортировка") }
        return unsupported
    }
}
