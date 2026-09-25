//
//  RoundView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI
import SwiftData
import UIKit

struct RoundView: View {
    @StateObject private var viewModel: RoundViewModel
    @StateObject private var frames = RoundFrames()
    @FocusState private var isAnswerFieldFocused: Bool
    @State private var containerHeight: CGFloat = 0
    @State private var frameHeight: CGFloat = 0
    @State private var answerBarHeight: CGFloat = 44
    @State private var pendingAnimatedHeightCatchUp = false
    @State private var showsResult = false
    @State private var morphProgress: Double = 0
    @State private var isMorphAnimating = false
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true

    private static let backgroundSpace = "roundBackground"

    private var barInset: CGFloat { isAnswerFieldFocused ? 6 : 24 }

    private var barBottomInset: CGFloat { isAnswerFieldFocused ? 6 : 24 - homeIndicatorInset }

    private var homeIndicatorInset: CGFloat { WindowMetrics.safeAreaInsets.bottom }

    private var stubGap: CGFloat { (containerHeight - barBottomInset - answerBarHeight) - frameHeight }

    private static let resultReveal = Animation.easeOut(duration: 0.32)

    init(mediaFacade: MediaFacadeProtocol, modelContext: ModelContext, mediaType: MediaType = .movie, filters: MediaFilters = MediaFilters(), frameCount: Int = 6) {
        _viewModel = StateObject(wrappedValue: RoundViewModel(mediaFacade: mediaFacade, modelContext: modelContext, mediaType: mediaType, filters: filters, frameCount: frameCount))
    }

    var body: some View {
        Group {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            } else {
                VStack(spacing: 0) {
                    FrameView(
                        imageURL: frames.displayedURL,
                        isWaitingForFrame: frames.isWaiting,
                        isProtected: isFrameProtected,
                        hidesSpinnerFromCapture: showsCaptureBanner,
                        onTapPrevious: { viewModel.showPreviousFrame() },
                        onTapNext: { viewModel.showNextFrame() }
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frameHeight = $0 }
                    .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) { resultStub }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
                .overlay(alignment: .bottom) { bottomActionBar }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        FrameIndicatorDots(
                            revealedCount: viewModel.revealedCount,
                            currentFrameIndex: viewModel.currentFrameIndex,
                            answeredFrameIndex: viewModel.answeredFrameIndex,
                            outcome: viewModel.outcome,
                            totalFrames: viewModel.frameCount
                        )
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(viewModel.attemptsRemaining)/\(viewModel.frameCount)")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .background {
            if frameHeight > 0 {
                RoundBackground(light: frames.hallLight, frameHeight: frameHeight,
                                isProtected: isFrameProtected, showsCaptureBanner: showsCaptureBanner,
                                coordinateSpace: Self.backgroundSpace)
            }
        }
        .coordinateSpace(.named(Self.backgroundSpace))
        .task { await viewModel.loadRound() }
        .task(id: FrameRequest(url: currentFrameURL, isRoundLoading: viewModel.isLoading)) {
            await frames.show(currentFrameURL, isRoundLoading: viewModel.isLoading)
        }
        .task(id: frameURLs) {
            await frames.preload(frameURLs)
        }
        .onChange(of: viewModel.hasSearched) { _, _ in
            pendingAnimatedHeightCatchUp = true
        }
        .onChange(of: viewModel.searchResults) { _, _ in
            pendingAnimatedHeightCatchUp = true
        }
        .gesture(
            DragGesture().onChanged { value in
                guard value.translation.height > 20, isAnswerFieldFocused else { return }
                DispatchQueue.main.async { resignKeyboard() }
            }
        )
        .onChange(of: viewModel.outcome) { _, newOutcome in
            isMorphAnimating = true
            if newOutcome != nil {
                isAnswerFieldFocused = false
                showsResult = true
                withAnimation(.smooth, completionCriteria: .logicallyComplete) {
                    morphProgress = 1
                } completion: {
                    isMorphAnimating = false
                }
            } else {
                withAnimation(Self.resultReveal) { showsResult = false }
                withAnimation(.smooth, completionCriteria: .logicallyComplete) {
                    morphProgress = 0
                } completion: {
                    isMorphAnimating = false
                }
            }
        }
    }

    private var frameURLs: [URL] {
        guard !viewModel.isLoading, let media = viewModel.mediaItemWithBackdrops else { return [] }
        return media.backdrops.prefix(viewModel.frameCount).compactMap { URL(string: $0.filePath) }
    }

    private var currentFrameURL: URL? {
        frameURLs[safe: viewModel.currentFrameIndex]
    }

    private func startNewRound() {
        answerBarHeight = 44
        pendingAnimatedHeightCatchUp = false
        Task { await viewModel.loadRound() }
    }

    private var bottomActionBar: some View {
        ZStack(alignment: .bottom) {
            AnswerInputBar(
                answerText: $viewModel.answerText,
                searchResults: viewModel.searchResults,
                hasSearched: viewModel.hasSearched,
                isFocused: $isAnswerFieldFocused,
                onSelectSuggestion: { viewModel.selectSuggestion($0) },
                onSubmit: submitIfReady,
                onAnswerTextChange: { await viewModel.searchAnswer() },
                onVisibleHeightChange: updateAnswerBarHeight,
                hasOutcome: viewModel.outcome != nil
            )
            .opacity((1 - morphProgress) * (isInputBlocked ? 0.5 : 1))
            .allowsHitTesting(morphProgress < 0.5)

            GeometryReader { proxy in
                AnswerBarActionShape(
                    progress: morphProgress,
                    width: proxy.size.width,
                    isBlocked: isSubmitBlocked,
                    isTransitioning: isMorphAnimating,
                    onSubmit: submitIfReady,
                    onNewGame: startNewRound
                )
            }
            .frame(height: suggestionRowHeight)
        }
        .padding(.horizontal, barInset)
        .padding(.bottom, barBottomInset)
        .animation(.smooth(duration: 0.25), value: isAnswerFieldFocused)
        .disabled(isInputBlocked)
    }

    @ViewBuilder
    private var resultStub: some View {
        if showsResult, let outcome = viewModel.outcome, let media = viewModel.mediaItemWithBackdrops {
            ResultStubStage(item: media.item,
                            mediaType: viewModel.mediaType,
                            details: viewModel.details,
                            outcome: outcome,
                            attemptsUsed: max(viewModel.attemptsMade, 1),
                            frameCount: viewModel.frameCount,
                            filters: viewModel.filters,
                            genreNames: viewModel.genreNames,
                            topInset: frameHeight,
                            restingOffset: max(0, (stubGap - ResultStubMetrics.height) / 2))
        }
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private var isFrameProtected: Bool {
        isScreenProtected && viewModel.outcome == nil
    }

    private var showsCaptureBanner: Bool {
        isFrameProtected && frames.hasPresentedFrame
    }

    private var isFrameReady: Bool {
        frames.displayedURL != nil && frames.displayedURL == currentFrameURL
    }

    private var isSubmitBlocked: Bool {
        isInputBlocked || (viewModel.outcome == nil && !isFrameReady)
    }

    private func submitIfReady() {
        guard !isSubmitBlocked else { return }
        viewModel.submitAnswer()
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

private struct FrameRequest: Equatable {
    let url: URL?
    let isRoundLoading: Bool
}

private struct RoundViewPreviewHost: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        RoundView(mediaFacade: PreviewMediaFacade(), modelContext: modelContext)
    }
}

#Preview {
    RoundViewPreviewHost()
        .modelContainer(for: [RoundRecord.self, WatchedRecord.self], inMemory: true)
}
