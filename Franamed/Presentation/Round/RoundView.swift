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
    @State private var fullHeight: CGFloat = 0
    @State private var frameHeight: CGFloat = 0
    @State private var answerBarHeight: CGFloat = 44
    @State private var pendingAnimatedHeightCatchUp = false
    @State private var morphProgress: Double = 0
    @State private var isMorphAnimating = false
    @State private var keyboardLift: CGFloat = 0
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true
    @State private var isStubLeaving = false
    @AppStorage(DebugSettings.resultStubPlacementKey) private var stubPlacement = ResultStubPlacement.behindForm

    private static let backgroundSpace = "roundBackground"

    private static let focusedBarInset: CGFloat = 6
    private static let restingBarInset: CGFloat = 24

    private var barInset: CGFloat { isAnswerFieldFocused ? Self.focusedBarInset : Self.restingBarInset }

    private var barBottomInset: CGFloat {
        isAnswerFieldFocused ? Self.focusedBarInset : Self.restingBarInset - homeIndicatorInset
    }

    private var homeIndicatorInset: CGFloat { WindowMetrics.safeAreaInsets.bottom }

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
                        image: frames.displayedImage,
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
                .background {
                    Color.clear
                        .ignoresSafeArea(.keyboard)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if !isAnswerFieldFocused || height > fullHeight { fullHeight = height }
                        }
                }
                .overlay(alignment: .bottom) { bottomActionBar }
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let keyboardHeight = WindowMetrics.size.height - frame.minY
            keyboardLift = max(0, keyboardHeight + Self.focusedBarInset - Self.restingBarInset)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            withAnimation(ResultStubPeek.keyboardSettleAnimation) { keyboardLift = 0 }
        }
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
        withAnimation(ResultStubPeek.exitAnimation) { isStubLeaving = true }
        Task {
            await viewModel.loadRound()
            isStubLeaving = false
        }
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
        .background(alignment: .bottom) { stubAnchor }
        .padding(.horizontal, barInset)
        .padding(.bottom, barBottomInset)
        .animation(.smooth(duration: 0.25), value: isAnswerFieldFocused)
        .disabled(isInputBlocked)
    }

    @ViewBuilder
    private var resultStub: some View {
        if !viewModel.isLoading, !isStubLeaving, frames.hasPresentedFrame, let media = viewModel.mediaItemWithBackdrops {
            ResultStubPeek(placement: stubPlacement,
                           item: media.item,
                           mediaType: viewModel.mediaType,
                           details: viewModel.details,
                           outcome: viewModel.outcome,
                           attemptsMade: viewModel.attemptsMade,
                           revealedCount: viewModel.revealedCount,
                           currentFrame: viewModel.currentFrameIndex,
                           hallLight: frames.hallLight.mean,
                           recordingLight: showsCaptureBanner ? CaptureWarningBanner.hallLight.mean : nil,
                           frameCount: viewModel.frameCount,
                           filters: viewModel.filters,
                           genreNames: viewModel.genreNames,
                           isTucked: isStubTucked,
                           keyboardLift: keyboardLift,
                           restOffset: stubRestOffset,
                           formWidth: WindowMetrics.size.width - barInset * 2)
                .id(media.item.id)
                .transition(.asymmetric(insertion: .identity,
                                        removal: .offset(x: WindowMetrics.size.width)))
        }
    }

    private var stubAnchor: some View {
        Color.clear
            .frame(height: 0)
            .overlay(alignment: .bottom) { resultStub }
            .geometryGroup()
    }

    private var isStubTucked: Bool {
        viewModel.outcome == nil && answerBarHeight > suggestionRowHeight + 1
    }

    private var stubRestOffset: CGFloat {
        let restingBarTop = fullHeight - (Self.restingBarInset - homeIndicatorInset) - suggestionRowHeight
        let gap = restingBarTop - frameHeight
        let restingStubTop = frameHeight + max(0, (gap - ResultStubMetrics.height) / 2)
        return restingStubTop + ResultStubMetrics.height - restingBarTop - suggestionRowHeight
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
