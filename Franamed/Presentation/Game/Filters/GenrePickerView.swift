//
//  GenrePickerView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.08.2026.
//

import SwiftUI

struct GenrePickerView: View {
    @ObservedObject var viewModel: RoundFiltersViewModel
    @State private var searchText = ""

    private var filteredGenres: [Genre] {
        guard !searchText.isEmpty else { return viewModel.genres }
        return viewModel.genres.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List(filteredGenres) { genre in
            Button {
                viewModel.toggleGenre(genre.id)
            } label: {
                HStack {
                    Text(genre.name)
                    Spacer()
                    if isSelected(genre) {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .searchable(text: $searchText)
        .navigationTitle("Жанры")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сброс") {
                    viewModel.filters.genres = nil
                }
            }
        }
        .task {
            await viewModel.loadGenres()
        }
    }

    private func isSelected(_ genre: Genre) -> Bool {
        viewModel.filters.genres?.contains(genre.id) == true
    }
}

#Preview {
    NavigationStack {
        GenrePickerView(viewModel: RoundFiltersViewModel(movieFacade: PreviewMovieFacade(), filters: MovieFilters(), frameCount: 6))
    }
}
