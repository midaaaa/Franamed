//
//  RoundView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI
import UIKit

struct RoundView: View {
    @StateObject private var viewModel: RoundViewModel
    @StateObject private var frames = RoundFrames()
    @State private var phone = HallPhone()
    @State private var isPhoneHeld = false
    @AppStorage(DebugSettings.phonePortraitKey) private var isPhonePortrait = false
    @AppStorage(DebugSettings.phoneSlowFinderKey) private var phoneSlowFinder = true
    @AppStorage(DebugSettings.phoneBloomKey) private var phoneBloom = 0.0
    @AppStorage(DebugSettings.screenBloomKey) private var screenBloom = 0.0
    @AppStorage(DebugSettings.phoneGridKey) private var showsPhoneGrid = false
    @AppStorage(DebugSettings.phoneWideKey) private var isPhoneWide = false
    @AppStorage(DebugSettings.phoneColorKey) private var phoneColor = HallPhoneColor.custom
    @AppStorage(DebugSettings.phoneCustomColorKey) private var phoneCustomColor = HallPhoneColor.custom
    @State private var isPickingPhoneColor = false
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
    @State private var roundNumber = 0
    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @AppStorage(DebugSettings.resultStubPlacementKey) private var stubPlacement = ResultStubPlacement.behindForm

    private let mode: TicketGameMode

    private static let backgroundSpace = "roundBackground"

    private static let focusedBarInset: CGFloat = 6
    private static let restingBarInset: CGFloat = 24

    private var barInset: CGFloat { isAnswerFieldFocused ? Self.focusedBarInset : Self.restingBarInset }

    private var barBottomInset: CGFloat {
        isAnswerFieldFocused ? Self.focusedBarInset : Self.restingBarInset - homeIndicatorInset
    }

    private var homeIndicatorInset: CGFloat { WindowMetrics.safeAreaInsets.bottom }

    init(mediaFacade: MediaFacadeProtocol, mediaType: MediaType = .movie, mode: TicketGameMode = .random, filters: MediaFilters = MediaFilters(), frameCount: Int = 6, shuffle: ShuffleMode = .smart) {
        self.mode = mode
        _viewModel = StateObject(wrappedValue: RoundViewModel(mediaFacade: mediaFacade, mediaType: mediaType, source: mode.roundSource, filters: filters, frameCount: frameCount, shuffle: shuffle))
    }

    var body: some View {
        Group {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            } else {
                VStack(spacing: 0) {
                    FrameView()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frameHeight = $0 }
                    .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .overlay {
                    HallPhoneSurface(phone: phone, frameHeight: frameHeight,
                                     onToggleOrientation: { isPhonePortrait.toggle() },
                                     onTapPrevious: { viewModel.showPreviousFrame() },
                                     onTapNext: { viewModel.showNextFrame() })
                }
                .background {
                    Color.clear
                        .ignoresSafeArea(.keyboard)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if !isAnswerFieldFocused || height > fullHeight { fullHeight = height }
                        }
                }
                .overlay(alignment: .bottom) { bottomActionBar }
                .navigationBarTitleDisplayMode(.inline)
                #if DEBUG
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Телефон", systemImage: isPhonePortrait ? "iphone" : "iphone.landscape") {
                            Toggle(isOn: $showsPhoneGrid) {
                                Text("Сетка")
                                Text("Линии 3×3")
                            }
                            Picker(selection: $isPhoneWide) {
                                Text("4:3").tag(false)
                                Text("16:9").tag(true)
                            } label: {
                                Text("Кадр камеры")
                                Text("16:9 ближе в 1,33 раза")
                            }
                            .pickerStyle(.menu)
                            Toggle(isOn: $phoneSlowFinder) {
                                Text("Экран 30 fps")
                                Text("Как у камеры")
                            }
                            levelPicker("Свет от телефона", "Ореол вокруг экрана", $phoneBloom)
                            levelPicker("Свет от кадра", "Ореол вокруг экрана в зале", $screenBloom)
                            ControlGroup {
                                colorButton(HallPhoneColor.white)
                                colorButton(HallPhoneColor.black)
                                colorButton(phoneCustomColor)
                                Button("Свой цвет", systemImage: "paintpalette") { isPickingPhoneColor = true }
                            } label: {
                                Text("Цвет корпуса")
                            }
                            .controlGroupStyle(.palette)
                        }
                    }
                }
                .sheet(isPresented: $isPickingPhoneColor) {
                    ColorPicker("Цвет корпуса", selection: Binding(
                        get: { Color(uiColor: HallPhoneColor.uiColor(phoneColor)) },
                        set: { color in
                            phoneCustomColor = HallPhoneColor.hex(UIColor(color))
                            phoneColor = phoneCustomColor
                        }
                    ), supportsOpacity: false)
                    .padding()
                    .presentationDetents([.height(120)])
                }
                #endif
            }
        }
        .background {
            if frameHeight > 0 {
                RoundBackground(light: frames.hallLight, frameHeight: frameHeight, picture: frames.picture,
                                isWaiting: frames.isWaiting && frames.picture == nil, phone: phone,
                                isProtected: isFrameProtected, showsCaptureBanner: showsCaptureBanner,
                                coordinateSpace: Self.backgroundSpace)
            }
        }
        .coordinateSpace(.named(Self.backgroundSpace))
        .onChange(of: viewModel.outcome) { _, outcome in phone.isLocked = outcome != nil }
        .onChange(of: isAnswerFieldFocused) { _, focused in if focused { phone.stow() } else { phone.unstow() } }
        .interactiveDismissDisabled(isPhoneHeld)
        .onAppear { phone.onHeldChange = { isPhoneHeld = $0 } }
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

    private func colorButton(_ hex: Int) -> some View {
        Button {
            phoneColor = hex
        } label: {
            Image(uiImage: HallPhoneColor.swatch(hex, isSelected: phoneColor == hex))
        }
    }

    private func levelPicker(_ title: String, _ detail: String, _ level: Binding<Double>) -> some View {
        Picker(selection: level) {
            Text("Выкл").tag(0.0)
            Text("Слабо").tag(0.5)
            Text("Сильно").tag(1.0)
        } label: {
            Text(title)
            Text(detail)
        }
        .pickerStyle(.menu)
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
        roundNumber += 1
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
                           mode: mode,
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
                .id(StubIdentity(itemID: media.item.id, round: roundNumber))
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
        let stubHeight = ResultStubMetrics.height(edgeStyle: TicketEdgeStyle(hasScallops: hasScallops))
        let restingStubTop = frameHeight + max(0, (gap - stubHeight) / 2)
        return restingStubTop + stubHeight - restingBarTop - suggestionRowHeight
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

    private var isSubmitBlocked: Bool {
        isInputBlocked || (viewModel.outcome == nil && !frames.hasPresentedFrame)
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

private struct StubIdentity: Hashable {
    let itemID: Int
    let round: Int
}

#Preview {
    RoundView(mediaFacade: PreviewMediaFacade())
}
