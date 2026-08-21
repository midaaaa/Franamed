//
//  SuggestionRow.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import Foundation

enum SuggestionRow: Identifiable {
    case media(MediaItem)
    case empty

    var id: AnyHashable {
        switch self {
        case .media(let item): item.id
        case .empty: "empty"
        }
    }
}
