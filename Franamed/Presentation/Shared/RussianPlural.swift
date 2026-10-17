//
//  RussianPlural.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import Foundation

enum RussianPlural {
    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        let remainder100 = count % 100
        let remainder10 = count % 10
        if (11...14).contains(remainder100) { return many }
        switch remainder10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }

    static func titles(_ count: Int, mediaType: MediaType) -> String {
        switch mediaType {
        case .movie: "\(count) \(form(count, one: "фильм", few: "фильма", many: "фильмов"))"
        case .tv: "\(count) \(form(count, one: "сериал", few: "сериала", many: "сериалов"))"
        }
    }
}
