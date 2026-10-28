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
    @AppStorage(DebugSettings.phoneNewGesturesKey) private var isNewPhoneGestures = true
    @AppStorage(DebugSettings.statsMocksKey) private var isStatsMocked = false
    @State private var mockStats: RoundStats?
    @State private var isPickingPhoneColor = false
    @FocusState private var isAnswerFieldFocused: Bool
    @State private var fullHeight: CGFloat = 0
    @State private var frameHeight: CGFloat = 0
    @State private var frameMidX: CGFloat = 0
    @State private var frameWidth: CGFloat = 0
    @State private var answerBarHeight: CGFloat = 44
    @State private var pendingAnimatedHeightCatchUp = false
    @State private var morphProgress: Double = 0
    @State private var isMorphAnimating = false
    @State private var keyboardLift: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var barBottom: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var fold: ClosedRange<CGFloat>?
    @State private var highestBarBottom: CGFloat = 0
    @State private var windowReference = WindowReference()
    @Environment(\.windowGeometry) private var window
    @Environment(\.displayScale) private var displayScale
    @Environment(\.resultStubWidth) private var stubWidth
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true
    @State private var isStubLeaving = false
    @State private var roundNumber = 0
    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @AppStorage(DebugSettings.resultStubPlacementKey) private var stubPlacement = ResultStubPlacement.behindForm

    @State private var ticketBeforeAnswer: PlaylistTicket?
    @State private var roundStamp: Double?
    @State private var isFormDismissed = false
    @State private var formCollapse: CGFloat = 0
    @State private var isShareLifted = false
    @Binding private var isDismissLocked: Bool
    private let mode: TicketGameMode
    @ObservedObject private var playlists: PlaylistsViewModel
    private let playlistID: String?
    private let ticketSeed: UInt64
    private let onPlaylistEmpty: () -> Void

    private nonisolated static let backgroundSpace = "roundBackground"
    private nonisolated static let contentSpace = "roundContent"
    private static let formCollapsedSide: CGFloat = 44
    private static let formCollapseDuration = 0.32
    private static let formFadeDuration = 0.12

    private static let focusedBarInset: CGFloat = 6
    private static let restingBarInset: CGFloat = 24
    private static let foldGap: CGFloat = 12
    private static let stubBarGap: CGFloat = 32

    private var barInset: CGFloat { isAnswerFieldFocused ? Self.focusedBarInset : Self.restingBarInset }

    private static let suggestionsTopMargin: CGFloat = 8
    private static let frameMaxHeightShare: CGFloat = 0.45
    private static let formMaxWidth: CGFloat = 640

    private var suggestionsRestRows: Int {
        switch window.size.height {
        case ..<1000: minVisibleSuggestions
        case ..<1250: minVisibleSuggestions + 1
        default: minVisibleSuggestions + 2
        }
    }

    private var frameMaxWidth: CGFloat {
        guard window.size.height > 0 else { return .infinity }
        return window.size.height * Self.frameMaxHeightShare * 16 / 9
    }

    private var formOuterWidth: CGFloat {
        let preferred = min(frameWidth > 0 ? frameWidth : window.size.width, Self.formMaxWidth)
        return min(window.size.width, max(preferred, stubWidth + barInset * 2))
    }

    private var suggestionsMaxHeight: CGFloat {
        let measured = highestBarBottom > 0 ? highestBarBottom : barBottom
        let barBottom = measured > 0 ? measured : fullHeight - (Self.restingBarInset - homeIndicatorInset)
        let available = barBottom - suggestionRowHeight - Self.suggestionsTopMargin
        return max(suggestionsContentHeight(rows: minVisibleSuggestions), available.rounded(.down))
    }

    private var barBottomInset: CGFloat {
        isAnswerFieldFocused ? Self.focusedBarInset : Self.restingBarInset - homeIndicatorInset
    }

    private var homeIndicatorInset: CGFloat { window.safeAreaInsets.bottom }

    private var foldLift: CGFloat {
        guard let fold, contentHeight > 0 else { return 0 }
        let bottom = contentHeight - barBottomInset
        let top = bottom - suggestionRowHeight
        guard top < fold.upperBound + Self.foldGap, bottom > fold.lowerBound - Self.foldGap else { return 0 }
        return max(0, bottom - (fold.lowerBound - Self.foldGap))
    }

    private var centerShift: CGFloat {
        let insets = window.safeAreaInsets
        let safeWidth = window.size.width - insets.leading - insets.trailing
        return window.shiftToCenter(fromMidX: insets.leading + safeWidth / 2,
                                    room: (safeWidth - max(frameWidth, formOuterWidth)) / 2)
    }

    init(mediaFacade: MediaFacadeProtocol, mediaType: MediaType = .movie, mode: TicketGameMode = .random, filters: MediaFilters = MediaFilters(), frameCount: Int = 6, shuffle: ShuffleMode = .smart, playlists: PlaylistsViewModel, playlistID: String? = nil, ticketSeed: UInt64 = FlipTear.randomSeed(), isDismissLocked: Binding<Bool> = .constant(false), onPlaylistEmpty: @escaping () -> Void = {}) {
        _isDismissLocked = isDismissLocked
        self.onPlaylistEmpty = onPlaylistEmpty
        self.mode = mode
        self.playlists = playlists
        self.playlistID = playlistID
        self.ticketSeed = ticketSeed
        _viewModel = StateObject(wrappedValue: RoundViewModel(mediaFacade: mediaFacade, mediaType: mediaType, source: mode.roundSource, filters: filters, frameCount: frameCount, shuffle: shuffle, playlistId: playlistID))
    }

    var body: some View {
        Group {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            } else {
                VStack(spacing: 0) {
                    FrameView(maxWidth: frameMaxWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        frameWidth = width
                        frames.displayPixelWidth = width * displayScale
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frameHeight = $0 }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.backgroundSpace)).midX } action: {
                        frameMidX = $0
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .offset(x: centerShift)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .readsHorizontalFold($fold)
                .overlay {
                    HallPhoneSurface(phone: phone, frameHeight: frameHeight, frameMidX: frameMidX,
                                     isNewGestures: isNewPhoneGestures,
                                     onToggleOrientation: { isPhonePortrait.toggle() },
                                     onTapPrevious: { viewModel.showPreviousFrame() },
                                     onTapNext: { viewModel.showNextFrame() })
                }
                .background {
                    Color.clear
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            fullHeight = $0
                            highestBarBottom = 0
                        }
                        .ignoresSafeArea(.keyboard)
                }
                .overlay(alignment: .bottom) { bottomActionBar.offset(x: centerShift) }
                .coordinateSpace(.named(Self.contentSpace))
                .navigationBarTitleDisplayMode(.inline)
                #if DEBUG
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Телефон", systemImage: isPhonePortrait ? "iphone" : "iphone.landscape") {
                            Picker(selection: $isNewPhoneGestures) {
                                Text("Старые").tag(false)
                                Text("Новые").tag(true)
                            } label: {
                                Text("Жесты")
                                Text(phoneGesturesNote)
                            }
                            .pickerStyle(.menu)
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
                RoundBackground(light: frames.hallLight, frameHeight: frameHeight, frameMidX: frameMidX,
                                picture: frames.picture,
                                isWaiting: frames.isWaiting && frames.picture == nil, phone: phone,
                                isProtected: isFrameProtected, showsCaptureBanner: showsCaptureBanner,
                                coordinateSpace: Self.backgroundSpace)
                    .environment(\.isHallCovered, isShareLifted)
            }
        }
        .coordinateSpace(.named(Self.backgroundSpace))
        .onChange(of: viewModel.isPlaylistEmpty) { _, isEmpty in
            if isEmpty { onPlaylistEmpty() }
        }
        .onChange(of: viewModel.outcome) { _, outcome in
            if outcome == nil { phone.closeApp() }
            mockStats = outcome == nil || !isStatsMocked ? nil
                : viewModel.mediaItemWithBackdrops.map { RoundStatsMock.next(itemID: $0.item.id) }
        }
        .task(id: roundStatsToShow) {
            guard let outcome = viewModel.outcome, let stats = roundStatsToShow else { return }
            await showPhoneStats(stats, for: outcome)
        }
        .onChange(of: isAnswerFieldFocused) { _, focused in
            if focused { phone.stow() } else if viewModel.outcome == nil { phone.unstow() } else { phone.forgetStow() }
        }
        .onChange(of: isPhoneHeld || isShareLifted, initial: true) { _, locked in isDismissLocked = locked }
        .onAppear {
            phone.onHeldChange = { isPhoneHeld = $0 }
            phone.onNoticeRewake = { [phone] in
                Task { phone.setNotice(await HallPhoneAppRender.lockScreen(time: .now)) }
            }
        }
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
        .onChange(of: viewModel.recordedFinishes) { _, _ in
            refreshPlaylist()
        }
        .gesture(
            DragGesture().onChanged { value in
                guard value.translation.height > 20, isAnswerFieldFocused else { return }
                DispatchQueue.main.async { resignKeyboard() }
            }
        )
        .background(WindowReader(reference: windowReference))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardHeight = dockedKeyboardHeight(screenFrame: frame)
            keyboardLift = Self.keyboardLift(forHeight: keyboardHeight)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            keyboardHeight = 0
            withAnimation(ResultStubPeek.keyboardSettleAnimation) { keyboardLift = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let height = dockedKeyboardHeight(screenFrame: frame)
            guard height != keyboardHeight else { return }
            keyboardHeight = height
            withAnimation(ResultStubPeek.keyboardSettleAnimation) { keyboardLift = Self.keyboardLift(forHeight: height) }
        }
        .onChange(of: viewModel.outcome) { _, newOutcome in
            isMorphAnimating = true
            if newOutcome != nil {
                isAnswerFieldFocused = false
                ticketBeforeAnswer = storedPlaylistTicket
                let morphsViaStamp = nextAction.stamp != nil
                if morphsViaStamp { collapseForm() }
                let morph = morphsViaStamp ? AnswerBarActionShape.stampMorphAnimation : .smooth
                withAnimation(morph, completionCriteria: .logicallyComplete) {
                    morphProgress = 1
                } completion: {
                    isMorphAnimating = false
                }
            } else {
                ticketBeforeAnswer = nil
                roundStamp = nil
                isFormDismissed = false
                formCollapse = 0
                withAnimation(.smooth, completionCriteria: .logicallyComplete) {
                    morphProgress = 0
                } completion: {
                    isMorphAnimating = false
                }
            }
        }
    }

    private var phoneGesturesNote: String {
        isNewPhoneGestures ? "Тап без задержки, поворот или зум" : "Двойной тап, всё сразу"
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

    // MARK: Phone stats

    private static let phoneStatsDelay = Duration.milliseconds(900)

    private var roundStatsToShow: RoundStats? {
        isStatsMocked ? mockStats : viewModel.stats
    }

    private func showPhoneStats(_ stats: RoundStats, for outcome: RoundOutcome) async {
        try? await Task.sleep(for: Self.phoneStatsDelay)
        guard !Task.isCancelled, viewModel.outcome == outcome else { return }
        let phoneStats = PhoneStats(stats: stats, solvedAtFrame: outcome == .correct ? viewModel.attemptsMade : nil,
                                    frameCount: viewModel.frameCount)
        let pictures = await HallPhoneAppRender.pictures(phoneStats)
        guard !Task.isCancelled, viewModel.outcome == outcome else { return }
        phone.showApp(pictures)
    }

    // MARK: Playlist

    private static let stampSteps: [Double] = (1...16).map { 0.5 - cos(Double($0) / 16 * .pi) / 2 }
    private static let stampStepDelay = Duration.milliseconds(28)
    private static let stampBackDelay = Duration.milliseconds(220)

    private var storedPlaylistTicket: PlaylistTicket? {
        playlistID.flatMap(playlists.ticket(id:))
    }

    private var answeredTicket: PlaylistTicket? {
        guard let outcome = viewModel.outcome, let before = ticketBeforeAnswer ?? storedPlaylistTicket else { return nil }
        return before.answering(isCorrect: outcome == .correct)
    }

    private var playlistFinish: PlaylistFinish? {
        guard let before = ticketBeforeAnswer ?? storedPlaylistTicket, let after = answeredTicket else { return nil }
        return after.finish(comparedTo: before)
    }

    private var playlistTicket: PlaylistTicket? {
        guard var ticket = answeredTicket ?? storedPlaylistTicket else { return nil }
        if playlistFinish != nil, let roundStamp {
            ticket.stampProgress = roundStamp
            ticket.isStampGold = ticket.isPerfect
        }
        return ticket
    }

    private var nextAction: AnswerBarNext {
        guard mode == .collection else { return AnswerBarNext(title: "Дальше") }
        guard let ticket = answeredTicket ?? storedPlaylistTicket, ticket.isFinished else {
            return AnswerBarNext(title: "Следующий")
        }
        if ticket.isPerfect {
            return AnswerBarNext(title: "Играть дальше", badge: "100%", stamp: playlistFinish)
        }
        return AnswerBarNext(title: "Переиграть", badge: "\(ticket.correctPercent)%", stamp: playlistFinish)
    }

    private func collapseForm() {
        withAnimation(.easeIn(duration: Self.formCollapseDuration)) { formCollapse = 1 }
        withAnimation(.easeOut(duration: Self.formFadeDuration).delay(Self.formCollapseDuration - Self.formFadeDuration)) {
            isFormDismissed = true
        }
    }

    private func stampOnBackIfNeeded() {
        guard playlistFinish != nil, roundStamp == nil, let playlistID,
              let item = viewModel.mediaItemWithBackdrops?.item.id else { return }
        roundStamp = 0
        Task { @MainActor in
            try? await Task.sleep(for: Self.stampBackDelay)
            for (index, step) in Self.stampSteps.enumerated() {
                guard viewModel.mediaItemWithBackdrops?.item.id == item, viewModel.outcome != nil else { return }
                roundStamp = step
                if index == Self.stampSteps.count - 1 { Haptics.shared.play(.stamp) }
                try? await Task.sleep(for: Self.stampStepDelay)
            }
            await playlists.reloadProgress()
            playlists.revealStamp(playlistID)
        }
    }

    private func refreshPlaylist() {
        guard playlistID != nil else { return }
        Task { await playlists.reloadProgress() }
    }

    // MARK: Share

    private func startShare(_ content: ResultStubContent, launch: ShareLaunch) {
        guard !isShareLifted, let outcome = viewModel.outcome, let media = viewModel.mediaItemWithBackdrops,
              let presenter = launch.presenter() else { return }
        let answerIndex = outcome == .correct ? viewModel.attemptsMade - 1 : viewModel.currentFrameIndex
        var material = ShareMaterial(content: content.withoutCursor(),
                                     solvedAtFrame: outcome == .correct ? viewModel.attemptsMade : nil,
                                     frames: frames.shareFrames(first: frameURLs.first, answer: frameURLs[safe: answerIndex]),
                                     roundSize: window.size)
        material.stubWidth = stubWidth
        let model = ShareSheetModel(material: material, launch: launch,
                                    posterPath: media.posterPath ?? viewModel.details?.posterPath)
        ShareSheetController.present(model: model, from: presenter, onLift: { isShareLifted = true },
                                     onFinish: { isShareLifted = false })
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
            .environment(\.suggestionsMaxHeight, suggestionsMaxHeight)
            .environment(\.suggestionsRestRows, suggestionsRestRows)
            .clipShape(FormCollapseShape(progress: formCollapse, side: Self.formCollapsedSide))
            .opacity((isFormDismissed ? 0 : 1) * (isInputBlocked ? 0.5 : 1))
            .allowsHitTesting(morphProgress < 0.5)

            GeometryReader { proxy in
                AnswerBarActionShape(
                    progress: morphProgress,
                    width: proxy.size.width,
                    isBlocked: isSubmitBlocked,
                    isTransitioning: isMorphAnimating,
                    next: nextAction,
                    onSubmit: submitIfReady,
                    onNewGame: startNewRound
                )
            }
            .frame(height: suggestionRowHeight)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.contentSpace)).maxY } action: {
            barBottom = $0
            highestBarBottom = highestBarBottom > 0 ? min(highestBarBottom, $0) : $0
        }
        .background(alignment: .bottom) { stubAnchor }
        .padding(.horizontal, barInset)
        .frame(maxWidth: formOuterWidth)
        .padding(.bottom, barBottomInset + foldLift)
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
                           foldTop: foldStubTop,
                           restOffset: stubRestOffset,
                           formWidth: formOuterWidth - barInset * 2,
                           playlist: playlistTicket,
                           ticketSeed: FlipTear.seed(ticket: ticketSeed, round: roundNumber),
                           onBackShown: stampOnBackIfNeeded,
                           isLifted: isShareLifted,
                           onShare: startShare)
                .id(StubIdentity(itemID: media.item.id, round: roundNumber))
                .transition(.asymmetric(insertion: .identity,
                                        removal: .offset(x: window.size.width)))
        }
    }

    private var stubAnchor: some View {
        Color.clear
            .frame(height: 0)
            .overlay(alignment: .bottom) { resultStub }
            .geometryGroup()
    }

    private var isStubTucked: Bool {
        viewModel.outcome == nil && foldStubTop == nil && answerBarHeight > suggestionRowHeight + 1
    }

    private var foldStubTop: CGFloat? {
        guard foldLift > 0, viewModel.outcome == nil, let fold, barBottom > 0 else { return nil }
        return max(0, fold.upperBound - barBottom - ResultStubPeek.peekHeight(stubWidth: stubWidth))
    }

    private var stubRestOffset: CGFloat {
        let restingBarTop = fullHeight - (Self.restingBarInset - homeIndicatorInset) - suggestionRowHeight
        let gap = restingBarTop - frameHeight
        let stubHeight = TicketStubMetrics.height(width: stubWidth, edgeStyle: TicketEdgeStyle(hasScallops: hasScallops))
        let restingStubTop = frameHeight + max(0, gap - stubHeight - Self.stubBarGap)
        return restingStubTop + stubHeight - restingBarTop - suggestionRowHeight
    }

    private static func keyboardLift(forHeight height: CGFloat) -> CGFloat {
        height > 0 ? max(0, height + focusedBarInset - restingBarInset) : 0
    }

    private func dockedKeyboardHeight(screenFrame: CGRect) -> CGFloat {
        guard let window = windowReference.window, let screen = window.windowScene?.screen,
              screenFrame.width >= screen.bounds.width - 1 else { return 0 }
        let frame = window.convert(screenFrame, from: screen.coordinateSpace)
        guard frame.maxY >= window.bounds.maxY - 1 else { return 0 }
        return max(0, window.bounds.maxY - frame.minY)
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
    RoundView(mediaFacade: PreviewMediaFacade(), playlists: PlaylistsViewModel())
}

private struct FormCollapseShape: Shape {
    var progress: CGFloat
    let side: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard progress > 0 else { return Path(rect.insetBy(dx: -2000, dy: -2000)) }
        let height = min(rect.height, side)
        let width = rect.width - (rect.width - height) * progress
        let frame = CGRect(x: rect.maxX - width, y: rect.maxY - height, width: width, height: height)
        return Path(roundedRect: frame, cornerRadius: height / 2)
    }
}
