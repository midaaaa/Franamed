//
//  SuggestionRow.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import Foundation

enum SuggestionRow: Identifiable {
    case movie(Movie)
    case empty

    var id: AnyHashable {
        switch self {
        case .movie(let movie): movie.id
        case .empty: "empty"
        }
    }
}
