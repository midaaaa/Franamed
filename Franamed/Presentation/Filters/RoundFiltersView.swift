//
//  RoundFiltersView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.08.2026.
//

import SwiftUI

struct RoundFiltersView: View {
    private static let earliestYear = 1888

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RoundFiltersViewModel
    let onApply: (RoundSetup) -> Void

    init(mediaFacade: MediaFacadeProtocol, source: RoundSource, mediaType: MediaType, setup: RoundSetup, onApply: @escaping (RoundSetup) -> Void) {
        _viewModel = StateObject(wrappedValue: RoundFiltersViewModel(mediaFacade: mediaFacade, source: source, mediaType: mediaType, initialSetup: setup))
        self.onApply = onApply
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
                if viewModel.source == .tmdb {
                    AdultFilterSection(includeAdult: $viewModel.filters.includeAdult,
                                       mediaType: viewModel.mediaType)
                }
                DifficultyFilterSection(frameCount: $viewModel.frameCount)
                switch viewModel.source {
                case .tmdb: SortByFilterSection(sortBy: $viewModel.filters.sortBy, mediaType: viewModel.mediaType)
                case .curated: ShuffleFilterSection(shuffle: $viewModel.shuffle)
                }
                GenresFilterSection(viewModel: viewModel)

                OptionalThresholdFilterSection(
                    title: "Рейтинг",
                    footer: "\(viewModel.mediaType.displayName) с рейтингом не ниже указанного.",
                    range: 0...10,
                    step: 0.5,
                    defaultValue: RoundFiltersViewModel.defaultMinRating,
                    formattedValue: { $0.formatted(.number.precision(.fractionLength(1))) },
                    isEnabled: $viewModel.limitRating,
                    value: $viewModel.filters.minRating
                )

                YearRangeFilterSection(
                    earliestYear: Self.earliestYear,
                    currentYear: RoundFiltersViewModel.currentYear,
                    footerText: yearSectionFooterText,
                    isEnabled: $viewModel.limitYears,
                    yearFrom: $viewModel.yearFrom,
                    yearTo: $viewModel.yearTo
                )

                OptionalThresholdFilterSection(
                    title: "Голоса",
                    footer: "Отсекает случайные оценки — рейтинг от пары голосов ненадёжен.",
                    range: 0...5000,
                    step: 100,
                    defaultValue: RoundFiltersViewModel.defaultMinVoteCount,
                    formattedValue: { Int($0).formatted() },
                    isEnabled: $viewModel.limitVoteCount,
                    value: minVoteCountBinding
                )

                LanguageFilterSection(selectedCodes: $viewModel.filters.originalLanguages)
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(viewModel.hasChanges)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { applyButton }
            .task { await viewModel.loadGenres() }
            .task(id: viewModel.previewFilters) { await viewModel.refreshPreview(filters: viewModel.previewFilters) }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if viewModel.hasChanges {
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
            Button("Очистить") {
                viewModel.clearFilters()
            }
        }
    }

    private var applyButton: some View {
        Button {
            onApply(viewModel.setup)
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
}

#Preview {
    RoundFiltersView(mediaFacade: PreviewMediaFacade(), source: .tmdb, mediaType: .movie, setup: RoundSetup()) { _ in }
}

#Preview("Курируемый") {
    RoundFiltersView(mediaFacade: PreviewMediaFacade(), source: .curated, mediaType: .movie, setup: RoundSetup()) { _ in }
}
