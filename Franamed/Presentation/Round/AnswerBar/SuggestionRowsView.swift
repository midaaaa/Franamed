//
//  SuggestionRowsView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct SuggestionRowsView: View {
    let rows: [SuggestionRow]
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(for: row)
                    .padding(.vertical, 12)
                    .padding(.leading, suggestionsLeadingInset)
                    .padding(.trailing, 12)

                if index != rows.count - 1 {
                    Divider()
                        .frame(height: suggestionDividerHeight)
                        .padding(.leading, suggestionsLeadingInset)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(for row: SuggestionRow) -> some View {
        switch row {
        case .media(let item):
            Button {
                onSelect(item)
            } label: {
                Text(item.title)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .empty:
            Text("Nothing found")
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
