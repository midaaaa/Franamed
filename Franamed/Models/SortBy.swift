//
//  SortBy.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.08.2026.
//

import Foundation

enum SortBy: Hashable, CaseIterable {
    case popularityDesc
    case ratingDesc
    case releaseDateDesc

    var displayName: String {
        switch self {
        case .popularityDesc: "По популярности"
        case .ratingDesc: "По рейтингу"
        case .releaseDateDesc: "По дате выхода"
        }
    }

    func tmdbValue(for mediaType: MediaType) -> String {
        switch self {
        case .popularityDesc:
            return "popularity.desc"
        case .ratingDesc:
            return "vote_average.desc"
        case .releaseDateDesc:
            switch mediaType {
            case .movie: return "primary_release_date.desc"
            case .tv: return "first_air_date.desc"
            }
        }
    }
}
