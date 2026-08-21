//
//  MoviesCountFormatter.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 19.08.2026.
//

import Foundation

enum MoviesCountFormatter {
    private static let maxReachablePages = 500
    private static let resultsPerPage = 20
    static let maxReachableResults = maxReachablePages * resultsPerPage

    static func applyButtonTitle(for resultsCount: Int?, mediaType: MediaType) -> String {
        guard let resultsCount else {
            return "Применить"
        }

        let cappedCount = min(resultsCount, maxReachableResults)
        guard cappedCount > 0 else {
            return "Ничего не найдено"
        }

        let countText = cappedCount >= maxReachableResults ? "10 000+" : cappedCount.formatted()
        return "Применить (~\(countText) \(pluralizedWord(for: cappedCount, mediaType: mediaType)))"
    }

    private static func pluralizedWord(for count: Int, mediaType: MediaType) -> String {
        let remainder100 = count % 100
        let remainder10 = count % 10

        let forms: (one: String, few: String, many: String) = switch mediaType {
        case .movie: ("фильм", "фильма", "фильмов")
        case .tv: ("сериал", "сериала", "сериалов")
        }

        if (11...14).contains(remainder100) {
            return forms.many
        }

        switch remainder10 {
        case 1: return forms.one
        case 2, 3, 4: return forms.few
        default: return forms.many
        }
    }
}
