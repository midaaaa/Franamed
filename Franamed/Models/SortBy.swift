//
//  SortBy.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.08.2026.
//

import Foundation

enum SortBy: String, CaseIterable {
    case popularityDesc = "popularity.desc"
    case voteAverageDesc = "vote_average.desc"
    case releaseDateDesc = "primary_release_date.desc"

    var displayName: String {
        switch self {
        case .popularityDesc: "По популярности"
        case .voteAverageDesc: "По рейтингу"
        case .releaseDateDesc: "По дате выхода"
        }
    }
}
