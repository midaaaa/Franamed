//
//  RoundFiltersView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.08.2026.
//

import SwiftUI

struct RoundFiltersView: View {
    private static let earliestYear = 1888
    private static let currentYear = Calendar.current.component(.year, from: .now)
    private static let defaultYearFrom = 1990
    private static let defaultMinRating = 5.0
    private static let defaultMinVoteCount = 100.0

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RoundFiltersViewModel
    let onApply: (RoundSetup) -> Void

    private let initialSetup: RoundSetup

    @State private var limitYears: Bool
    @State private var yearFrom: Int
    @State private var yearTo: Int

    @State private var limitRating: Bool
    @State private var limitVoteCount: Bool

    init(mediaFacade: MediaFacadeProtocol, mediaType: MediaType, setup: RoundSetup, onApply: @escaping (RoundSetup) -> Void) {
        _viewModel = StateObject(wrappedValue: RoundFiltersViewModel(mediaFacade: mediaFacade, mediaType: mediaType, filters: setup.filters, frameCount: setup.frameCount))
        self.onApply = onApply
        self.initialSetup = setup

        let filters = setup.filters
        _limitYears = State(initialValue: filters.yearRange != nil)
        _yearFrom = State(initialValue: filters.yearRange?.lowerBound ?? Self.defaultYearFrom)
        _yearTo = State(initialValue: filters.yearRange?.upperBound ?? Self.currentYear)
        _limitRating = State(initialValue: filters.minRating != nil)
        _limitVoteCount = State(initialValue: filters.minVoteCount != nil)
    }

    private var previewFilters: MediaFilters {
        var result = viewModel.filters
        result.yearRange = limitYears ? min(yearFrom, yearTo)...max(yearFrom, yearTo) : nil
        result.minRating = limitRating ? viewModel.filters.minRating : nil
        result.minVoteCount = limitVoteCount ? viewModel.filters.minVoteCount : nil
        return result
    }

    private var hasChanges: Bool {
        previewFilters != initialSetup.filters || viewModel.frameCount != initialSetup.frameCount
    }

    private var frameCountBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.frameCount) },
            set: { viewModel.frameCount = Int($0) }
        )
    }

    private var minVoteCountBinding: Binding<Double?> {
        Binding(
            get: { viewModel.filters.minVoteCount.map(Double.init) },
            set: { viewModel.filters.minVoteCount = $0.map { Int($0) } }
        )
    }

    private var yearSectionFooterText: String {
        switch viewModel.mediaType {
        case .movie: "Диапазон года выхода фильма."
        case .tv: "Диапазон года начала показа сериала."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                AdultFilterSection(includeAdult: $viewModel.filters.includeAdult,
                                   mediaType: viewModel.mediaType)
                DifficultyFilterSection(frameCount: $viewModel.frameCount)
                SortByFilterSection(sortBy: $viewModel.filters.sortBy, mediaType: viewModel.mediaType)
                GenresFilterSection(viewModel: viewModel)

                OptionalThresholdFilterSection(
                    title: "Рейтинг",
                    footer: "\(viewModel.mediaType.displayName) с рейтингом не ниже указанного.",
                    range: 0...10,
                    step: 0.5,
                    defaultValue: Self.defaultMinRating,
                    formattedValue: { $0.formatted(.number.precision(.fractionLength(1))) },
                    isEnabled: $limitRating,
                    value: $viewModel.filters.minRating
                )

                YearRangeFilterSection(
                    earliestYear: Self.earliestYear,
                    currentYear: Self.currentYear,
                    footerText: yearSectionFooterText,
                    isEnabled: $limitYears,
                    yearFrom: $yearFrom,
                    yearTo: $yearTo
                )

                OptionalThresholdFilterSection(
                    title: "Голоса",
                    footer: "Отсекает случайные оценки — рейтинг от пары голосов ненадёжен.",
                    range: 0...5000,
                    step: 100,
                    defaultValue: Self.defaultMinVoteCount,
                    formattedValue: { Int($0).formatted() },
                    isEnabled: $limitVoteCount,
                    value: minVoteCountBinding
                )

                LanguageFilterSection(selectedCodes: $viewModel.filters.originalLanguages)
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasChanges)
            .onChange(of: limitRating) { _, newValue in
                if newValue && viewModel.filters.minRating == nil {
                    viewModel.filters.minRating = Self.defaultMinRating
                }
            }
            .onChange(of: limitVoteCount) { _, newValue in
                if newValue && viewModel.filters.minVoteCount == nil {
                    viewModel.filters.minVoteCount = Int(Self.defaultMinVoteCount)
                }
            }
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { applyButton }
            .task { await viewModel.loadGenres() }
            .task(id: previewFilters) { await viewModel.refreshPreview(filters: previewFilters) }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if hasChanges {
                Menu {
                    Button("Выйти без сохранения", role: .destructive) {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Сброс") {
                resetAll()
            }
        }
    }

    private var applyButton: some View {
        Button {
            applyYearRange()
            applyRatingAndVoteCount()
            onApply(RoundSetup(filters: viewModel.filters, frameCount: viewModel.frameCount))
            dismiss()
        } label: {
            ZStack {
                Text(viewModel.applyButtonTitle)
                    .opacity(viewModel.isCheckingPreview ? 0 : 1)
                if viewModel.isCheckingPreview {
                    ProgressView()
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(viewModel.isApplyDisabled ? .gray : .accentColor)
        .disabled(viewModel.isApplyDisabled)
        .padding(.horizontal, 32)
        .padding(.top, 8)
    }

    private func resetAll() {
        let defaults = RoundSetup()
        viewModel.filters = defaults.filters
        viewModel.frameCount = defaults.frameCount
        limitYears = false
        yearFrom = Self.defaultYearFrom
        yearTo = Self.currentYear
        limitRating = false
        limitVoteCount = false
    }

    private func applyYearRange() {
        guard limitYears else {
            viewModel.filters.yearRange = nil
            return
        }
        viewModel.filters.yearRange = min(yearFrom, yearTo)...max(yearFrom, yearTo)
    }

    private func applyRatingAndVoteCount() {
        if !limitRating {
            viewModel.filters.minRating = nil
        }
        if !limitVoteCount {
            viewModel.filters.minVoteCount = nil
        }
    }
}

#Preview {
    RoundFiltersView(mediaFacade: PreviewMediaFacade(), mediaType: .movie, setup: RoundSetup()) { _ in }
}
