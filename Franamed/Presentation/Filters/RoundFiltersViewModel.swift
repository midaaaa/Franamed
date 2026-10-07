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
    let source: RoundSource
    let mediaType: MediaType
    @Published var filters: MediaFilters
    @Published var frameCount: Int
    @Published var shuffle: ShuffleMode
    @Published private(set) var genres: [Genre] = []
    @Published private(set) var isLoadingGenres = false
    @Published private(set) var previewResultsCount: Int?
    @Published private(set) var isCheckingPreview = false

    @Published var limitYears: Bool
    @Published var yearFrom: Int
    @Published var yearTo: Int

    @Published var limitRating: Bool {
        didSet {
            if limitRating && filters.minRating == nil {
                filters.minRating = Self.defaultMinRating
            }
        }
    }

    @Published var limitVoteCount: Bool {
        didSet {
            if limitVoteCount && filters.minVoteCount == nil {
                filters.minVoteCount = Int(Self.defaultMinVoteCount)
            }
        }
    }

    private let initialSetup: RoundSetup
    static let currentYear = Calendar.current.component(.year, from: .now)
    static let defaultYearFrom = 1990
    static let defaultMinRating = 5.0
    static let defaultMinVoteCount = 100.0

    private let mediaFacade: MediaFacadeProtocol

    init(mediaFacade: MediaFacadeProtocol, source: RoundSource, mediaType: MediaType, initialSetup: RoundSetup) {
        self.mediaFacade = mediaFacade
        self.source = source
        self.mediaType = mediaType
        self.initialSetup = initialSetup
        self.filters = initialSetup.filters
        self.frameCount = initialSetup.frameCount
        self.shuffle = initialSetup.shuffle
        self.limitYears = initialSetup.filters.yearRange != nil
        self.yearFrom = initialSetup.filters.yearRange?.lowerBound ?? Self.defaultYearFrom
        self.yearTo = initialSetup.filters.yearRange?.upperBound ?? Self.currentYear
        self.limitRating = initialSetup.filters.minRating != nil
        self.limitVoteCount = initialSetup.filters.minVoteCount != nil
    }

    var previewFilters: MediaFilters {
        var result = filters
        result.yearRange = limitYears ? min(yearFrom, yearTo)...max(yearFrom, yearTo) : nil
        result.minRating = limitRating ? filters.minRating : nil
        result.minVoteCount = limitVoteCount ? filters.minVoteCount : nil
        return result
    }

    var hasChanges: Bool {
        setup != initialSetup
    }

    var isApplyDisabled: Bool {
        isCheckingPreview || previewResultsCount == 0
    }

    var applyButtonTitle: String {
        MoviesCountFormatter.applyButtonTitle(for: previewResultsCount, mediaType: mediaType)
    }

    var setup: RoundSetup {
        RoundSetup(filters: previewFilters, frameCount: frameCount, shuffle: shuffle)
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
            previewResultsCount = switch source {
            case .tmdb: try await mediaFacade.fetchResultsCount(mediaType: mediaType, filters: filters)
            case .curated: try await mediaFacade.fetchCuratedCount(mediaType: mediaType, filters: filters)
            }
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

    func clearFilters() {
        filters = MediaFilters()
        limitYears = false
        yearFrom = Self.defaultYearFrom
        yearTo = Self.currentYear
        limitRating = false
        limitVoteCount = false
    }
}
