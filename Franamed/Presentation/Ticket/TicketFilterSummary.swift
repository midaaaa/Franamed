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
        case rating(String)
        case list([String], separator: String)
    }

    let label: String
    let value: Value
    var isSet = true
}

struct TicketFilterSummary {
    let frames: TicketField
    let years: TicketField
    let rating: TicketField
    let genres: TicketField
    let votes: TicketField
    let languages: TicketField

    static let defaultFrameCount = RoundSetup().frameCount

    init(setup: RoundSetup, genreNames: [String]) {
        let filters = setup.filters
        frames = TicketField(label: "Кадры", value: .text("\(setup.frameCount)"),
                             isSet: setup.frameCount != Self.defaultFrameCount)
        years = Self.years(filters.yearRange)
        rating = Self.rating(filters.minRating)
        genres = Self.list("Жанры", genreNames, separator: ", ")
        votes = Self.votes(filters.minVoteCount)
        languages = Self.list("Языки", filters.originalLanguages?.map { $0.uppercased() } ?? [], separator: " ")
    }

    private static func list(_ label: String, _ names: [String], separator: String) -> TicketField {
        guard !names.isEmpty else { return TicketField(label: label, value: .text("все"), isSet: false) }
        return TicketField(label: label, value: .list(names, separator: separator))
    }

    private static func rating(_ value: Double?) -> TicketField {
        guard let value else { return TicketField(label: "Рейтинг", value: .text("любой"), isSet: false) }
        return TicketField(label: "Рейтинг",
                           value: .rating("\(value.formatted(.number.precision(.fractionLength(0...1))))+"))
    }

    private static func votes(_ count: Int?) -> TicketField {
        guard let count else { return TicketField(label: "Оценки", value: .text("все"), isSet: false) }
        return TicketField(label: "Оценки", value: .text("\(count)+"))
    }

    private static func years(_ range: ClosedRange<Int>?) -> TicketField {
        guard let range else { return TicketField(label: "Годы", value: .text("все"), isSet: false) }
        return TicketField(label: "Годы", value: .text(yearsText(range)))
    }

    private static func yearsText(_ range: ClosedRange<Int>) -> String {
        let (low, high) = (range.lowerBound, range.upperBound)
        if low == high { return "\(low)" }
        if low % 10 == 0, high == low + 9 { return "\(String(low).suffix(2))-е" }
        if high >= Calendar.current.component(.year, from: .now) { return "с \(low)" }
        if low <= MediaFilters.earliestYear { return "до \(high)" }
        return "\(low)–\(high)"
    }
}
