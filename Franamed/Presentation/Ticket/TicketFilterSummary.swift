//
//  TicketFilterSummary.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import Foundation

struct TicketField {
    enum Value {
        case text(String)
        case symbol(name: String, text: String)
        case list([String])
    }

    let label: String
    let value: Value
    var isPlaceholder = false
}

struct TicketFilterSummary {
    let genres: TicketField
    let rating: TicketField
    let year: TicketField
    let votes: TicketField
    let languages: TicketField

    init(filters: MediaFilters, genreNames: [String]) {
        genres = Self.genres(genreNames)
        rating = Self.rating(filters.minRating)
        year = Self.year(filters.yearRange)
        votes = Self.votes(filters.minVoteCount)
        languages = Self.languages(filters.originalLanguages)
    }

    private static func genres(_ names: [String]) -> TicketField {
        guard !names.isEmpty else {
            return TicketField(label: "Жанр", value: .text("Любые"), isPlaceholder: true)
        }
        return TicketField(label: "Жанр", value: .list(names))
    }

    private static func rating(_ value: Double?) -> TicketField {
        guard let value else {
            return TicketField(label: "Рейтинг", value: .text("Любой"), isPlaceholder: true)
        }
        let text = "\(value.formatted(.number.precision(.fractionLength(0...1))))+"
        return TicketField(label: "Рейтинг", value: .symbol(name: "star.fill", text: text))
    }

    private static func year(_ range: ClosedRange<Int>?) -> TicketField {
        guard let range else {
            return TicketField(label: "Год", value: .text("Все годы"), isPlaceholder: true)
        }
        let text = range.lowerBound == range.upperBound
            ? "\(range.lowerBound)"
            : "\(range.lowerBound)–\(range.upperBound)"
        return TicketField(label: "Год", value: .text(text))
    }

    private static func votes(_ count: Int?) -> TicketField {
        guard let count else {
            return TicketField(label: "Оценки", value: .text("Неважно"), isPlaceholder: true)
        }
        return TicketField(label: "Оценки", value: .symbol(name: "person.fill", text: "\(count)+"))
    }

    private static func languages(_ codes: [String]?) -> TicketField {
        let names = codes?.map { $0.uppercased() } ?? []
        guard !names.isEmpty else {
            return TicketField(label: "Язык", value: .text("Любой"), isPlaceholder: true)
        }
        return TicketField(label: "Язык", value: .list(names))
    }
}
