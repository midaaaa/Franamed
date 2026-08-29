//
//  GenresFilterSection.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct GenresFilterSection: View {
    @ObservedObject var viewModel: RoundFiltersViewModel

    private var selectedNames: [String] {
        guard let selected = viewModel.filters.genres, !selected.isEmpty else { return [] }
        return viewModel.genres.filter { selected.contains($0.id) }.map(\.name)
    }

    var body: some View {
        Section {
            NavigationLink {
                GenrePickerView(viewModel: viewModel)
            } label: {
                summary.foregroundStyle(.secondary)
            }
        } header: {
            Text("Жанры")
        } footer: {
            Text("Достаточно совпадения хотя бы с одним жанром.")
        }
    }

    @ViewBuilder
    private var summary: some View {
        let names = selectedNames
        if names.isEmpty {
            Text("Все жанры")
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: names.count, through: 1, by: -1)), id: \.self) { shownCount in
                    let shown = names.prefix(shownCount).joined(separator: ", ")
                    let remaining = names.count - shownCount
                    Text(remaining > 0 ? "\(shown) +\(remaining)" : shown)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text("\(names.count)")
                    .lineLimit(1)
            }
        }
    }
}
