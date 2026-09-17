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
    @FocusState private var isAnswerFieldFocused: Bool
    @State private var containerHeight: CGFloat = 0
    @State private var frameHeight: CGFloat = 0
    @State private var answerBarHeight: CGFloat = 44
    @State private var pendingAnimatedHeightCatchUp = false
    @State private var stripTints: [ProjectorStripTint] = []
    @State private var displayedURL: URL?
    @State private var isBeamFillLit = true
    @State private var isWaitingForFrame = false
    @State private var beamAnimation: Animation?
    @State private var morphProgress: Double = 0
    @State private var isMorphAnimating = false
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true

    private var barInset: CGFloat { isAnswerFieldFocused ? 6 : 24 }

    private var barBottomInset: CGFloat { isAnswerFieldFocused ? 6 : 24 - homeIndicatorInset }

    private var homeIndicatorInset: CGFloat { WindowMetrics.safeAreaInsets.bottom }

    private var beamReferenceHeight: CGFloat {
        max(0, WindowMetrics.size.height - frameHeight - suggestionRowHeight)
    }

    private var beamGap: CGFloat { (containerHeight - barBottomInset - answerBarHeight) - frameHeight }
    private var beamHeight: CGFloat { max(beamGap, 1) }
    private var beamMaxExpectedGap: CGFloat { max(containerHeight * 0.25, 1) }

    private static let beamShrink = Animation.timingCurve(0.38, 0.7, 0.125, 1, duration: 0.28)
    private var beamIntensity: Double {
        guard beamGap > 0 else { return 0 }
        return Double(min(1, max(0, beamGap / beamMaxExpectedGap)))
    }

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
                        imageURL: displayedURL,
                        isWaitingForFrame: isWaitingForFrame,
                        isProtected: isScreenProtected && viewModel.outcome == nil,
                        onTapPrevious: { viewModel.showPreviousFrame() },
                        onTapNext: { viewModel.showNextFrame() }
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frameHeight = $0 }
                    .layoutPriority(1)

                    if viewModel.outcome == nil {
                        ProjectorBeam(
                            intensity: beamIntensity,
                            stripTints: stripTints,
                            isFillLit: isBeamFillLit,
                            referenceHeight: beamReferenceHeight,
                            isProtected: isScreenProtected,
                            showsSource: false
                        )
                            .frame(maxHeight: beamHeight)
                            .clipped()
                            .animation(beamAnimation, value: containerHeight)
                            .animation(.smooth(duration: 0.25), value: isAnswerFieldFocused)
                            .allowsHitTesting(false)
                    }

                    if let outcome = viewModel.outcome, let mediaItemWithBackdrops = viewModel.mediaItemWithBackdrops {
                        ResultBanner(
                            outcome: outcome,
                            movieTitle: mediaItemWithBackdrops.item.originalTitle
                        )
                        .padding(.top, 16)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
                    beamAnimation = newHeight < containerHeight ? Self.beamShrink : nil
                    containerHeight = newHeight
                }
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
        .task { await viewModel.loadRound() }
        .task(id: currentBackdropURL) {
            await transitionToCurrentFrame()
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
        guard !viewModel.isLoading, let mediaItemWithBackdrops = viewModel.mediaItemWithBackdrops else { return [] }
        return Array(mediaItemWithBackdrops.backdrops.prefix(viewModel
            .frameCount))
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

            if let cachedTints = ProjectorFrameTint.cachedTints(for: url) {
                stripTints = cachedTints
                isBeamFillLit = true
                isWaitingForFrame = false
                return
            }

            let tints = await Task.detached(priority: .userInitiated) {
                ProjectorFrameTint.averageStripTints(from: cachedImage, stripCount: 14)
            }.value
            guard !Task.isCancelled, url == currentBackdropURL else { return }
            ProjectorFrameTint.storeTints(tints, for: url)
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
                onSelectSuggestion: { viewModel.selectSuggestion($0) },
                onSubmit: { viewModel.submitAnswer() },
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
                    isBlocked: isInputBlocked,
                    isTransitioning: isMorphAnimating,
                    onSubmit: { viewModel.submitAnswer() },
                    onNewGame: startNewRound
                )
            }
            .frame(height: suggestionRowHeight)
        }
        .padding(.horizontal, barInset)
        .overlay(alignment: .top) { beamSource }
        .padding(.bottom, barBottomInset)
        .animation(.smooth(duration: 0.25), value: isAnswerFieldFocused)
        .disabled(isInputBlocked)
    }

    @ViewBuilder
    private var beamSource: some View {
        if viewModel.outcome == nil {
            ZStack(alignment: .bottom) {
                ProjectorSourceHalo()
                ProjectorLineSource()
            }
            .frame(height: beamHeight)
            .offset(y: -beamHeight)
            .opacity(max(beamIntensity, ProjectorBeam.imperceptibleOpacity))
            .allowsHitTesting(false)
        }
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
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

private struct RoundViewPreviewHost: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        RoundView(mediaFacade: PreviewMediaFacade(), modelContext: modelContext)
    }
}

#Preview {
    RoundViewPreviewHost()
        .modelContainer(for: [RoundRecord.self, WatchedMovieCache.self], inMemory: true)
}
