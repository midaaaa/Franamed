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
    @State private var containerHeight: CGFloat = 0
    @State private var frameHeight: CGFloat = 0
    @State private var answerBarHeight: CGFloat = 44
    @State private var pendingAnimatedHeightCatchUp = false
    @State private var stripTints: [ProjectorStripTint] = []
    @State private var displayedURL: URL?
    @State private var isBeamFillLit = true
    @State private var isWaitingForFrame = false
    @State private var morphProgress: Double = 0
    @State private var isMorphAnimating = false

    private var beamGap: CGFloat { (containerHeight - 8 - answerBarHeight) - frameHeight }
    private var beamMaxExpectedGap: CGFloat { max(containerHeight * 0.25, 1) }
    private var beamIntensity: Double {
        guard beamGap > 0 else { return 0 }
        return Double(min(1, max(0, beamGap / beamMaxExpectedGap)))
    }

    init(movieFacade: MovieFacadeProtocol) {
        _viewModel = StateObject(wrappedValue: RoundViewModel(movieFacade: movieFacade))
    }

    var body: some View {
        Group {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            } else {
                VStack(spacing: 0) {
                    FrameView(
                        imageURL: displayedURL,
                        isWaitingForFrame: isWaitingForFrame,
                        onTapPrevious: { viewModel.showPreviousFrame() },
                        onTapNext: { viewModel.showNextFrame() }
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frameHeight = $0 }
                    .layoutPriority(1)

                    if viewModel.outcome == nil {
                        ProjectorBeam(intensity: beamIntensity, stripTints: stripTints, isFillLit: isBeamFillLit)
                            .frame(maxHeight: max(beamGap, 0))
                            .clipped()
                            .allowsHitTesting(false)
                    }

                    if let outcome = viewModel.outcome, let movieWithBackdrops = viewModel.movieWithBackdrops {
                        ResultBanner(
                            outcome: outcome,
                            movieTitle: movieWithBackdrops.movie.originalTitle
                        )
                        .padding(.top, 16)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    containerHeight = $0
                }
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
        .task(id: currentBackdropURL) {
            await transitionToCurrentFrame()
        }
        .onChange(of: viewModel.hasSearched) { _, _ in
            pendingAnimatedHeightCatchUp = true
        }
        .onChange(of: viewModel.searchResults.map(\.id)) { _, _ in
            pendingAnimatedHeightCatchUp = true
        }
        .gesture(
            DragGesture().onChanged { value in
                if value.translation.height > 20 {
                    isAnswerFieldFocused = false
                }
            }
        )
        .onChange(of: viewModel.outcome) { _, newOutcome in
            isMorphAnimating = true
            if newOutcome != nil {
                isAnswerFieldFocused = false
                withAnimation(.smooth, completionCriteria: .logicallyComplete) {
                    morphProgress = 1
                } completion: {
                    isMorphAnimating = false
                }
            } else {
                withAnimation(.smooth, completionCriteria: .logicallyComplete) {
                    morphProgress = 0
                } completion: {
                    isMorphAnimating = false
                }
            }
        }
    }

    private var visibleBackdrops: [Backdrop] {
        guard !viewModel.isLoading, let movieWithBackdrops = viewModel.movieWithBackdrops else { return [] }
        return Array(movieWithBackdrops.backdrops.prefix(RoundViewModel.maxAttempts))
    }

    private var currentBackdropURL: URL? {
        guard let backdrop = visibleBackdrops[safe: viewModel.currentFrameIndex] else { return nil }
        return URL(string: backdrop.filePath)
    }

    private func transitionToCurrentFrame() async {
        guard let url = currentBackdropURL else {
            displayedURL = nil
            stripTints = []
            isBeamFillLit = false
            isWaitingForFrame = false
            return
        }
        guard url != displayedURL else { return }

        if let cachedImage = ImageCache.shared.image(for: url) {
            displayedURL = url
            let tints = await Task.detached(priority: .userInitiated) {
                ProjectorFrameTint.averageStripTints(from: cachedImage, stripCount: 14)
            }.value
            guard !Task.isCancelled, url == currentBackdropURL else { return }
            stripTints = tints
            isBeamFillLit = true
            isWaitingForFrame = false
            return
        }

        displayedURL = nil
        isBeamFillLit = false
        isWaitingForFrame = false

        let loadTask = Task { await ProjectorFrameTint.loadAndSample(url: url, stripCount: 14) }

        let timedOut = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask { _ = await loadTask.value; return false }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(180))
                return true
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        guard !Task.isCancelled else {
            loadTask.cancel()
            return
        }

        if timedOut {
            isWaitingForFrame = true
        }

        let tints = await loadTask.value
        guard !Task.isCancelled else { return }

        displayedURL = url
        stripTints = tints
        isBeamFillLit = true
        isWaitingForFrame = false
    }

    private var startNewRound: () -> Void {
        {
            answerBarHeight = 44
            pendingAnimatedHeightCatchUp = false
            Task { await viewModel.loadRound() }
        }
    }

    private var bottomActionBar: some View {
        ZStack(alignment: .bottom) {
            AnswerInputBar(
                answerText: $viewModel.answerText,
                searchResults: viewModel.searchResults,
                hasSearched: viewModel.hasSearched,
                isFocused: $isAnswerFieldFocused,
                onSelectSuggestion: { movie in viewModel.answerText = movie.title },
                onSubmit: { viewModel.submitAnswer() },
                onAnswerTextChange: { await viewModel.searchAnswer() },
                onVisibleHeightChange: updateAnswerBarHeight,
                showsSubmitButton: false,
                hasOutcome: viewModel.outcome != nil
            )
            .opacity((1 - morphProgress) * (isInputBlocked ? 0.5 : 1))
            .allowsHitTesting(morphProgress < 0.5)

            GeometryReader { proxy in
                AnswerBarActionShape(
                    progress: morphProgress,
                    width: proxy.size.width,
                    isBlocked: isInputBlocked,
                    isTransitioning: isMorphAnimating,
                    onSubmit: { viewModel.submitAnswer() },
                    onNewGame: startNewRound
                )
            }
            .frame(height: suggestionRowHeight)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .disabled(isInputBlocked)
    }

    private var isInputBlocked: Bool {
        viewModel.isLoading
    }

    private func updateAnswerBarHeight(_ newHeight: CGFloat) {
        if pendingAnimatedHeightCatchUp {
            pendingAnimatedHeightCatchUp = false
            withAnimation(.snappy) { answerBarHeight = newHeight }
        } else {
            answerBarHeight = newHeight
        }
    }
}

#Preview {
    RoundView(movieFacade: PreviewMovieFacade())
}
