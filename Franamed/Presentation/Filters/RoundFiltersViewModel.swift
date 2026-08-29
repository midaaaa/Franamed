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
    let mediaType: MediaType
    @Published var filters: MediaFilters
    @Published var frameCount: Int
    @Published private(set) var genres: [Genre] = []
    @Published private(set) var isLoadingGenres = false
    @Published private(set) var previewResultsCount: Int?
    @Published private(set) var isCheckingPreview = false

    private let mediaFacade: MediaFacadeProtocol

    init(mediaFacade: MediaFacadeProtocol, mediaType: MediaType, filters: MediaFilters, frameCount: Int) {
        self.mediaFacade = mediaFacade
        self.mediaType = mediaType
        self.filters = filters
        self.frameCount = frameCount
    }

    var isApplyDisabled: Bool {
        isCheckingPreview || previewResultsCount == 0
    }

    var applyButtonTitle: String {
        MoviesCountFormatter.applyButtonTitle(for: previewResultsCount, mediaType: mediaType)
    }

    func loadGenres() async {
        guard genres.isEmpty else { return }

        isLoadingGenres = true
        defer { isLoadingGenres = false }

        do {
            genres = try await mediaFacade.fetchGenres(mediaType: mediaType)
        } catch {
            genres = []
        }
    }

    func refreshPreview(filters: MediaFilters) async {
        isCheckingPreview = true

        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        do {
            previewResultsCount = try await mediaFacade.fetchResultsCount(mediaType: mediaType, filters: filters)
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
