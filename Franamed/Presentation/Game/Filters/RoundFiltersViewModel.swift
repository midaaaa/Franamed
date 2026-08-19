//
//  RoundFiltersViewModel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.08.2026.
//

import Foundation
import Combine

@MainActor
final class RoundFiltersViewModel: ObservableObject {
    @Published var filters: MovieFilters
    @Published var frameCount: Int
    @Published private(set) var genres: [Genre] = []
    @Published private(set) var isLoadingGenres = false
    @Published private(set) var previewResultsCount: Int?
    @Published private(set) var isCheckingPreview = false

    private let movieFacade: MovieFacadeProtocol

    init(movieFacade: MovieFacadeProtocol, filters: MovieFilters, frameCount: Int) {
        self.movieFacade = movieFacade
        self.filters = filters
        self.frameCount = frameCount
    }

    var isApplyDisabled: Bool {
        isCheckingPreview || previewResultsCount == 0
    }

    var applyButtonTitle: String {
        MoviesCountFormatter.applyButtonTitle(for: previewResultsCount)
    }

    func loadGenres() async {
        guard genres.isEmpty else { return }

        isLoadingGenres = true
        defer { isLoadingGenres = false }

        do {
            genres = try await movieFacade.fetchGenres()
        } catch {
            genres = []
        }
    }

    func refreshPreview(filters: MovieFilters) async {
        isCheckingPreview = true

        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        do {
            previewResultsCount = try await movieFacade.fetchResultsCount(filters: filters)
        } catch {
            previewResultsCount = 0
        }
        isCheckingPreview = false
    }

    func toggleGenre(_ id: Int) {
        var current = filters.genres ?? []
        if let index = current.firstIndex(of: id) {
            current.remove(at: index)
        } else {
            current.append(id)
        }
        filters.genres = current.isEmpty ? nil : current
    }
}
