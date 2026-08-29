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
        Grid(alignment: .topLeading,
             horizontalSpacing: TicketStyle.fieldColumnGap,
             verticalSpacing: TicketStyle.fieldRowSpacing) {
            GridRow {
                column(summary.genres).gridCellColumns(2)
                column(summary.rating)
            }
            GridRow {
                column(summary.year)
                column(summary.votes)
                column(summary.languages)
            }
        }
    }

    private func column(_ field: TicketField) -> some View {
        TicketFieldColumn(field: field)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TicketFieldColumn: View {
    let field: TicketField

    var body: some View {
        VStack(alignment: .leading, spacing: TicketStyle.fieldLabelSpacing) {
            Text(field.label)
                .font(TicketStyle.fieldLabel)
                .textCase(.uppercase)
                .tracking(TicketStyle.fieldLabelTracking)
            value
                .font(field.isPlaceholder ? TicketStyle.fieldPlaceholder : TicketStyle.fieldValue)
                .foregroundStyle(field.isPlaceholder ? TicketStyle.placeholderInk : Color.black)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.black)
    }

    @ViewBuilder
    private var value: some View {
        switch field.value {
        case .text(let text):
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(TicketStyle.minimumScale)
        case .symbol(let name, let text):
            HStack(spacing: TicketStyle.symbolTextSpacing) {
                Image(systemName: name)
                    .font(.system(size: TicketStyle.valueSymbolSize))
                Text(text)
            }
            .lineLimit(1)
            .minimumScaleFactor(TicketStyle.minimumScale)
        case .list(let names):
            AdaptiveNameList(names: names)
        }
    }
}

private struct AdaptiveNameList: View {
    let names: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: names.count, through: 1, by: -1)), id: \.self) { shownCount in
                Text(label(showing: shownCount))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text("\(names.count)")
                .lineLimit(1)
        }
    }

    private func label(showing count: Int) -> String {
        let shown = names.prefix(count).joined(separator: ", ")
        let remaining = names.count - count
        return remaining > 0 ? "\(shown) +\(remaining)" : shown
    }
}

#Preview("Комбинации фильтров") {
    let scenarios: [(String, MediaFilters, [String])] = [
        ("Пусто", MediaFilters(), []),
        ("Всё сразу", MediaFilters(
            genres: [1, 2, 3, 4], yearRange: 1990...2010, minRating: 7.0,
            minVoteCount: 500, originalLanguages: ["ru", "en", "fr"]
        ), ["Комедия", "Ужасы", "Триллер", "Драма"]),
        ("Длинные жанры + рейтинг", MediaFilters(genres: [1, 2], minRating: 7.0),
         ["Action & Adventure", "Sci-Fi & Fantasy"]),
        ("Один год", MediaFilters(yearRange: 2015...2015), []),
    ]

    return ScrollView {
        VStack(spacing: 16) {
            ForEach(scenarios, id: \.0) { label, filters, genreNames in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TicketFilterSummaryView(
                        summary: TicketFilterSummary(filters: filters, genreNames: genreNames)
                    )
                    .frame(width: 300, alignment: .leading)
                    .padding(TicketStyle.stubPadding)
                    .background(Color.white)
                }
            }
        }
        .padding()
    }
    .background(Color.black)
}
