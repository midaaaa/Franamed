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
    let onApply: (MovieFilters, Int) -> Void

    private let initialFilters: MovieFilters
    private let initialFrameCount: Int

    @State private var limitYears: Bool
    @State private var yearFrom: Int
    @State private var yearTo: Int

    @State private var limitRating: Bool
    @State private var limitVoteCount: Bool

    init(movieFacade: MovieFacadeProtocol, filters: MovieFilters, frameCount: Int, onApply: @escaping (MovieFilters, Int) -> Void) {
        _viewModel = StateObject(wrappedValue: RoundFiltersViewModel(movieFacade: movieFacade, filters: filters, frameCount: frameCount))
        self.onApply = onApply
        self.initialFilters = filters
        self.initialFrameCount = frameCount

        _limitYears = State(initialValue: filters.yearRange != nil)
        _yearFrom = State(initialValue: filters.yearRange?.lowerBound ?? Self.defaultYearFrom)
        _yearTo = State(initialValue: filters.yearRange?.upperBound ?? Self.currentYear)
        _limitRating = State(initialValue: filters.minRating != nil)
        _limitVoteCount = State(initialValue: filters.minVoteCount != nil)
    }

    private var previewFilters: MovieFilters {
        var result = viewModel.filters
        result.yearRange = limitYears ? min(yearFrom, yearTo)...max(yearFrom, yearTo) : nil
        result.minRating = limitRating ? viewModel.filters.minRating : nil
        result.minVoteCount = limitVoteCount ? viewModel.filters.minVoteCount : nil
        return result
    }

    private var hasChanges: Bool {
        previewFilters != initialFilters || viewModel.frameCount != initialFrameCount
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

    private var selectedGenreNamesSummary: String {
        guard let selectedIds = viewModel.filters.genres, !selectedIds.isEmpty else {
            return "Все жанры"
        }
        let names = viewModel.genres.filter { selectedIds.contains($0.id) }.map(\.name)
        let visibleCount = 2
        guard names.count > visibleCount else {
            return names.joined(separator: ", ")
        }
        let remaining = names.count - visibleCount
        return names.prefix(visibleCount).joined(separator: ", ") + " +\(remaining)"
    }

    var body: some View {
        NavigationStack {
            Form {
                difficultySection
                genresSection

                YearRangeFilterSection(
                    earliestYear: Self.earliestYear,
                    currentYear: Self.currentYear,
                    isEnabled: $limitYears,
                    yearFrom: $yearFrom,
                    yearTo: $yearTo
                )

                sortBySection

                OptionalThresholdFilterSection(
                    title: "Рейтинг",
                    footer: "Фильмы с рейтингом не ниже указанного.",
                    range: 0...10,
                    step: 0.5,
                    defaultValue: Self.defaultMinRating,
                    formattedValue: { $0.formatted(.number.precision(.fractionLength(1))) },
                    isEnabled: $limitRating,
                    value: $viewModel.filters.minRating
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

                Section {
                    Toggle("18+", isOn: $viewModel.filters.includeAdult)
                } footer: {
                    Text("Показывать фильмы с рейтингом 18+.")
                }
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

    private var difficultySection: some View {
        Section {
            HStack {
                Slider(value: frameCountBinding, in: 1...6, step: 1) {
                    Text("Сложность")
                }
                Text(viewModel.frameCount, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 16, alignment: .trailing)
            }
        } header: {
            Text("Сложность")
        } footer: {
            Text("Меньше кадров — сложнее, больше — легче.")
        }
    }

    private var genresSection: some View {
        Section {
            NavigationLink {
                GenrePickerView(viewModel: viewModel)
            } label: {
                Text(selectedGenreNamesSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } header: {
            Text("Жанры")
        } footer: {
            Text("Достаточно совпадения хотя бы с одним жанром.")
        }
    }

    private var sortBySection: some View {
        Section {
            Picker("Сортировка", selection: $viewModel.filters.sortBy) {
                ForEach(SortBy.allCases, id: \.self) { sortBy in
                    Text(sortBy.displayName).tag(sortBy)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Сортировка")
        } footer: {
            Text("Определяет, из каких фильмов собирается раунд: самых популярных, высокооценённых или новых.")
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
            onApply(viewModel.filters, viewModel.frameCount)
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
        viewModel.filters = MovieFilters()
        viewModel.frameCount = 6
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
    RoundFiltersView(movieFacade: PreviewMovieFacade(), filters: MovieFilters(), frameCount: 6) { _, _ in }
}
