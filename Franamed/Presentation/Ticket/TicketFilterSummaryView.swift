//
//  TicketFilterSummaryView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.08.2026.
//

import SwiftUI

struct TicketFilterSummaryView: View {
    let summary: TicketFilterSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 5)
            row(summary.frames, summary.years, summary.rating)
            Spacer(minLength: 4)
            TicketFieldColumn(field: summary.genres)
            Spacer(minLength: 4)
            row(summary.votes, summary.languages, nil)
        }
    }

    private func row(_ leading: TicketField, _ middle: TicketField, _ trailing: TicketField?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            TicketFieldColumn(field: leading)
                .frame(width: TicketStyle.fieldLeadingWidth, alignment: .leading)
            TicketFieldColumn(field: middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let trailing { TicketFieldColumn(field: trailing) } else { Color.clear.frame(height: 1) }
            }
            .frame(width: TicketStyle.fieldTrailingWidth, alignment: .leading)
        }
    }
}

private struct TicketFieldColumn: View {
    let field: TicketField

    var body: some View {
        TicketFieldCell(label: field.label) {
            value
                .font(TicketStyle.value(isSet: field.isSet))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var value: some View {
        switch field.value {
        case .text(let text):
            Text(text)
                .minimumScaleFactor(TicketStyle.minimumScale)
        case .rating(let text):
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: TicketStyle.valueSize * 0.9, weight: .bold))
                Text(text)
            }
            .minimumScaleFactor(TicketStyle.minimumScale)
        case .list(let names, let separator):
            TicketNameList(names: names, separator: separator)
        }
    }
}

#Preview("Комбинации фильтров") {
    let scenarios: [(String, RoundSetup, [String])] = [
        ("Пусто", RoundSetup(), []),
        ("Всё сразу", RoundSetup(filters: MediaFilters(
            genres: [1, 2, 3, 4], yearRange: 1990...2010, minRating: 7.5,
            minVoteCount: 500, originalLanguages: ["ru", "en", "fr"]
        ), frameCount: 3), ["Комедия", "Ужасы", "Триллер", "Драма"]),
        ("Длинные жанры + 80-е", RoundSetup(filters: MediaFilters(genres: [1, 2], yearRange: 1980...1989, minRating: 6)),
         ["Action & Adventure", "Sci-Fi & Fantasy"]),
        ("С 2015", RoundSetup(filters: MediaFilters(yearRange: 2015...2026), frameCount: 1), []),
    ]

    return ScrollView {
        VStack(spacing: 16) {
            ForEach(scenarios, id: \.0) { label, setup, genreNames in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TicketFilterSummaryView(summary: TicketFilterSummary(setup: setup, genreNames: genreNames))
                        .foregroundStyle(Color.black)
                        .frame(width: TicketStyle.stubBodyWidth, alignment: .leading)
                        .padding(TicketStyle.stubSideInset)
                        .background(TicketStyle.paper)
                }
            }
        }
        .padding()
    }
    .background(Color.black)
}
