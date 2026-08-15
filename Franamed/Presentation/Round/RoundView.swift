//
//  RoundView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct RoundView: View {
    @StateObject private var viewModel: RoundViewModel
    @FocusState private var isAnswerFieldFocused: Bool

    init(movieFacade: MovieFacadeProtocol) {
        _viewModel = StateObject(wrappedValue: RoundViewModel(movieFacade: movieFacade))
    }

    var body: some View {
        Group {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            } else {
                VStack(spacing: 16) {
                    FrameView(
                        backdrops: visibleBackdrops,
                        currentFrameIndex: viewModel.currentFrameIndex,
                        onTapPrevious: { viewModel.showPreviousFrame() },
                        onTapNext: { viewModel.showNextFrame() }
                    )

                    if let outcome = viewModel.outcome, let movieWithBackdrops = viewModel.movieWithBackdrops {
                        ResultBanner(
                            outcome: outcome,
                            movieTitle: movieWithBackdrops.movie.originalTitle
                        )
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) { bottomActionBar }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        FrameIndicatorDots(
                            revealedCount: viewModel.revealedCount,
                            currentFrameIndex: viewModel.currentFrameIndex,
                            answeredFrameIndex: viewModel.answeredFrameIndex,
                            outcome: viewModel.outcome
                        )
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(viewModel.attemptsRemaining)/\(RoundViewModel.maxAttempts)")
                    }
                }
            }
        }
        .task { await viewModel.loadRound() }
        .gesture(
            DragGesture().onChanged { value in
                if value.translation.height > 20 {
                    isAnswerFieldFocused = false
                }
            }
        )
    }

    private var visibleBackdrops: [Backdrop] {
        guard !viewModel.isLoading, let movieWithBackdrops = viewModel.movieWithBackdrops else { return [] }
        return Array(movieWithBackdrops.backdrops.prefix(RoundViewModel.maxAttempts))
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        Group {
            if viewModel.outcome == nil {
                AnswerInputBar(
                    answerText: $viewModel.answerText,
                    searchResults: viewModel.searchResults,
                    hasSearched: viewModel.hasSearched,
                    isFocused: $isAnswerFieldFocused,
                    onSelectSuggestion: { movie in viewModel.answerText = movie.title },
                    onSubmit: { viewModel.submitAnswer() },
                    onAnswerTextChange: { await viewModel.searchAnswer() }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                NewGameButton {
                    Task { await viewModel.loadRound() }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .disabled(viewModel.isLoading)
        .opacity(viewModel.isLoading ? 0.5 : 1)
        .animation(.snappy, value: viewModel.outcome)
    }
}

#Preview {
    RoundView(movieFacade: PreviewMovieFacade())
}
