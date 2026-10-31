//
//  PvPMatchView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI
import UIKit

struct PvPMatchView: View {
    let screen: PvPMatchScreen
    let mediaType: MediaType
    let onGuess: (MediaItem?, String) -> Void
    let onSkip: () -> Void

    @StateObject private var frames = RoundFrames()
    @StateObject private var search: PvPAnswerSearch
    @State private var phone = HallPhone()
    @State private var viewedFrame: Int?
    @State private var frameHeight: CGFloat = 0
    @State private var frameMidX: CGFloat = 0
    @State private var frameWidth: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var barBottom: CGFloat = 0
    @State private var highestBarBottom: CGFloat = 0
    @State private var answerBarHeight: CGFloat = suggestionRowHeight
    @State private var pendingAnimatedHeightCatchUp = false
    @FocusState private var isAnswerFocused: Bool
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true
    @Environment(\.windowGeometry) private var window
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private nonisolated static let space = "pvpMatch"
    private static let frameMaxHeightShare: CGFloat = 0.45
    private static let hudGap: CGFloat = 14
    private static let formMaxWidth: CGFloat = 640

    init(screen: PvPMatchScreen, mediaType: MediaType, mediaFacade: MediaFacadeProtocol,
         onGuess: @escaping (MediaItem?, String) -> Void, onSkip: @escaping () -> Void) {
        self.screen = screen
        self.mediaType = mediaType
        self.onGuess = onGuess
        self.onSkip = onSkip
        _search = StateObject(wrappedValue: PvPAnswerSearch(mediaFacade: mediaFacade))
    }

    private var frameURLs: [URL] {
        screen.frames.compactMap { PvPImageLinks.frame($0.path) }
    }

    private var displayedIndex: Int? {
        guard let shown = screen.shownFrame else { return nil }
        guard let viewedFrame, viewedFrame <= screen.viewableFrame ?? shown else { return shown }
        return viewedFrame
    }

    private var displayedURL: URL? {
        displayedIndex.flatMap { frameURLs[safe: $0] }
    }

    private var isProtected: Bool { isScreenProtected && screen.isProtected }

    private var frameMaxWidth: CGFloat {
        guard window.size.height > 0 else { return .infinity }
        return window.size.height * Self.frameMaxHeightShare * 16 / 9
    }

    private var homeIndicatorInset: CGFloat { window.safeAreaInsets.bottom }

    private var barInset: CGFloat { isAnswerFocused ? AnswerBarLayout.focusedInset : AnswerBarLayout.restingInset }

    private var barBottomInset: CGFloat {
        isAnswerFocused ? AnswerBarLayout.focusedInset : AnswerBarLayout.restingInset - homeIndicatorInset
    }

    private var formOuterWidth: CGFloat {
        min(window.size.width, min(frameWidth > 0 ? frameWidth : window.size.width, Self.formMaxWidth))
    }

    private var suggestionsMaxHeight: CGFloat {
        AnswerBarLayout.suggestionsMaxHeight(measuredBarBottom: highestBarBottom > 0 ? highestBarBottom : barBottom,
                                             fullHeight: fullHeight, homeIndicatorInset: homeIndicatorInset)
    }

    var body: some View {
        VStack(spacing: 0) {
            FrameView(maxWidth: frameMaxWidth)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frameHeight = $0 }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { frameWidth = $0 }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).midX } action: { frameMidX = $0 }
                .overlay { frameOverlay }
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .overlay {
            HallPhoneSurface(phone: phone, frameHeight: frameHeight, frameMidX: frameMidX,
                             onToggleOrientation: {},
                             onTapPrevious: { showFrame(by: -1) },
                             onTapNext: { showFrame(by: 1) })
        }
        .overlay(alignment: .top) {
            if frameHeight > 0 {
                hud.padding(.top, frameHeight + Self.hudGap)
            }
        }
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    fullHeight = $0
                    highestBarBottom = 0
                }
                .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .bottom) {
            if screen.stage == .playing {
                answerBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: screen.stage == .playing)
        .background {
            if frameHeight > 0 {
                RoundBackground(light: frames.hallLight, frameHeight: frameHeight, frameMidX: frameMidX,
                                picture: frames.picture, isWaiting: isFrameWaiting, phone: phone,
                                isProtected: isProtected, showsCaptureBanner: isProtected && frames.hasPresentedFrame,
                                coordinateSpace: Self.space)
            }
        }
        .coordinateSpace(.named(Self.space))
        .gesture(
            DragGesture().onChanged { value in
                guard value.translation.height > 20, isAnswerFocused else { return }
                DispatchQueue.main.async { AnswerBarLayout.resignKeyboard() }
            }
        )
        .onChange(of: search.hasSearched) { _, _ in pendingAnimatedHeightCatchUp = true }
        .onChange(of: search.results) { _, _ in pendingAnimatedHeightCatchUp = true }
        .task(id: PvPFrameRequest(url: displayedURL, isWaiting: isFrameWaiting)) {
            await frames.show(displayedURL, isRoundLoading: isFrameWaiting)
        }
        .task(id: frameURLs) { await frames.preload(frameURLs) }
        .onChange(of: screen.shownFrame) { _, _ in viewedFrame = nil }
        .onChange(of: screen.input.feedback) { _, feedback in
            guard let feedback else { return }
            Haptics.shared.play(feedback.correct ? .answerCorrect : .answerWrong)
        }
        .onChange(of: screen.stage) { old, new in
            if case .countdown = new { Haptics.shared.play(.tabBreak) }
            if new == .playing, old != .playing { Haptics.shared.play(.stamp) }
        }
        .onChange(of: isFieldLocked) { _, locked in
            if locked { isAnswerFocused = false }
        }
        .onChange(of: isAnswerFocused) { _, focused in
            if focused { phone.stow() } else { phone.unstow() }
        }
    }

    private var isFrameWaiting: Bool {
        switch screen.stage {
        case .picking, .preparing, .waiting: true
        case .playing: displayedURL != nil && !frames.hasPresentedFrame
        case .countdown, .watching: false
        }
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 12) {
            if let duel = screen.duel {
                PvPDuelBarsView(bars: duel)
            }
            if !screen.rivals.isEmpty {
                PvPRivalsView(rivals: screen.rivals)
            }
        }
        .frame(maxWidth: PvPStyle.maxWidth)
        .padding(.horizontal, PvPStyle.inset)
    }

    @ViewBuilder
    private var frameOverlay: some View {
        if let resume = screen.resumeIn {
            PvPCountdownNumber(value: resume)
        } else {
            switch screen.stage {
            case let .countdown(value):
                VStack(spacing: 6) {
                    PvPCountdownNumber(value: value)
                    if let text = screen.stageText {
                        Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                }
            case .picking, .preparing, .waiting, .watching:
                if let text = screen.stageText {
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 18)
                }
            case .playing:
                EmptyView()
            }
        }
    }

    private func showFrame(by step: Int) {
        guard let shown = screen.shownFrame else { return }
        let next = (displayedIndex ?? shown) + step
        guard (0...(screen.viewableFrame ?? shown)).contains(next) else { return }
        viewedFrame = next
    }

    // MARK: Answer

    private var answerBar: some View {
        ZStack(alignment: .bottom) {
            AnswerInputBar(
                answerText: $search.text,
                searchResults: search.results,
                hasSearched: search.hasSearched,
                isFocused: $isAnswerFocused,
                onSelectSuggestion: { search.select($0) },
                onSubmit: submit,
                onAnswerTextChange: { await search.search(mediaType: mediaType) },
                onVisibleHeightChange: updateAnswerBarHeight,
                hasOutcome: isFieldLocked
            )
            .environment(\.suggestionsMaxHeight, suggestionsMaxHeight)
            .environment(\.suggestionsRestRows, AnswerBarLayout.suggestionsRestRows(windowHeight: window.size.height))
            .opacity(isFieldLocked ? 0.5 : 1)

            GeometryReader { proxy in
                AnswerBarActionShape(progress: 0, width: proxy.size.width, isBlocked: !screen.input.isEnabled,
                                     isTransitioning: false, onSubmit: submit, onNewGame: {})
            }
            .frame(height: suggestionRowHeight)
        }
        .background(alignment: .bottom) {
            PvPStubPeek(screen: screen, mediaType: mediaType, viewedFrame: displayedIndex, isRaised: !isAnswerFocused,
                        isTucked: answerBarHeight > suggestionRowHeight + 1, width: formOuterWidth - barInset * 2)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY } action: {
            barBottom = $0
            highestBarBottom = highestBarBottom > 0 ? min(highestBarBottom, $0) : $0
        }
        .padding(.horizontal, barInset)
        .frame(maxWidth: formOuterWidth)
        .padding(.bottom, barBottomInset)
        .animation(.smooth(duration: 0.25), value: isAnswerFocused)
        .disabled(isFieldLocked)
    }

    private var isFieldLocked: Bool { !screen.input.isEnabled && !screen.input.isSending }

    private func updateAnswerBarHeight(_ newHeight: CGFloat) {
        if pendingAnimatedHeightCatchUp {
            pendingAnimatedHeightCatchUp = false
            withAnimation(.snappy) { answerBarHeight = newHeight }
        } else {
            answerBarHeight = newHeight
        }
    }

    private func submit() {
        guard screen.input.isEnabled else { return }
        if search.isEmpty {
            onSkip()
            return
        }
        let text = search.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = search.pick()
        search.reset()
        onGuess(item, text)
    }
}

private struct PvPFrameRequest: Equatable {
    let url: URL?
    let isWaiting: Bool
}

// MARK: - Parts

struct PvPCountdownNumber: View {
    let value: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(value)")
            .font(.system(size: 88, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : .snappy, value: value)
    }
}

#if DEBUG
private struct PvPMatchPreview: View {
    let state: PvPMatchState

    var body: some View {
        NavigationStack {
            if let match = PvPPreview.match(state) {
                PvPMatchView(screen: match, mediaType: .movie, mediaFacade: PreviewMediaFacade(), onGuess: { _, _ in }, onSkip: {})
                    .navigationTitle("Комната")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .providesWindowGeometry()
        .preferredColorScheme(.dark)
    }
}

#Preview("Подбор фильмов") { PvPMatchPreview(state: PvPMatchFixtures.loading) }
#Preview("Загрузка кадров") { PvPMatchPreview(state: PvPMatchFixtures.preparing) }
#Preview("Ждём остальных") { PvPMatchPreview(state: PvPMatchFixtures.preparedWaiting) }
#Preview("Загрузка кадров дуэли") { PvPMatchPreview(state: PvPMatchFixtures.duelPreparing) }
#Preview("Отсчёт") { PvPMatchPreview(state: PvPMatchFixtures.countdown) }
#Preview("Игра, думаю") { PvPMatchPreview(state: PvPMatchFixtures.playingThinking) }
#Preview("Игра, отправляю") { PvPMatchPreview(state: PvPMatchFixtures.playingAnswering) }
#Preview("Игра, соперник угадал") { PvPMatchPreview(state: PvPMatchFixtures.playingRivalSolved) }
#Preview("Игра, дедлайн") { PvPMatchPreview(state: PvPMatchFixtures.playingDeadline) }
#Preview("Игра, угадал") { PvPMatchPreview(state: PvPMatchFixtures.playingSolved) }
#Preview("Игра, зритель") { PvPMatchPreview(state: PvPMatchFixtures.playingSpectator) }
#Preview("Дуэль, игра") { PvPMatchPreview(state: PvPMatchFixtures.duelPlaying) }
#Preview("После паузы") { PvPMatchPreview(state: PvPMatchFixtures.resuming) }

#Preview("Цифра отсчёта") {
    PvPCountdownNumber(value: 3)
        .padding()
        .background(.black)
}
#endif
