//
//  PvPHallView.swift
//  Franamed
//
//  Created by Claude on 20.11.2026.
//

import SwiftUI
import UIKit

/// The PvP round, built from the same parts as `RoundView`: the Metal hall, the phone,
/// the answer form and the real result stub that flies up with the answer.
/// It stays on screen for the whole film — countdown, play and results — so the hall never cuts away.
/// The countdown and the round results are drawn on the cinema screen itself.
struct PvPHallView: View {
    let match: PvPMatchScreen?
    let reveal: PvPRevealScreen?
    var final: PvPFinalScreen?
    let isDuel: Bool
    let mediaType: MediaType
    let mediaFacade: MediaFacadeProtocol
    let onGuess: (MediaItem?, String) -> Void
    let onSkip: () -> Void
    var onAction: (PvPAction.Kind) -> Void = { _ in }
    /// Debug: extra fake players to check how the seats fill.
    var extraBots = 0

    @StateObject private var frames = RoundFrames()
    @StateObject private var search: PvPAnswerSearch
    @StateObject private var canvas = PvPScreenCanvas()
    @State private var phone = HallPhone()
    @State private var lastMatch: PvPMatchScreen?
    @State private var viewedFrame: Int?
    @State private var details: MediaDetails?
    @State private var missTokens: [String: Int] = [:]
    @State private var ticketSeed = FlipTear.randomSeed()
    @FocusState private var isAnswerFocused: Bool
    @State private var frameHeight: CGFloat = 0
    @State private var frameMidX: CGFloat = 0
    @State private var frameWidth: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var barBottom: CGFloat = 0
    @State private var highestBarBottom: CGFloat = 0
    @State private var answerBarHeight: CGFloat = suggestionRowHeight
    @State private var pendingAnimatedHeightCatchUp = false
    @State private var keyboardLift: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var windowReference = WindowReference()
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true
    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @AppStorage(DebugSettings.resultStubPlacementKey) private var stubPlacement = ResultStubPlacement.behindForm
    @Environment(\.windowGeometry) private var window
    @Environment(\.displayScale) private var displayScale
    @Environment(\.resultStubWidth) private var stubWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private nonisolated static let space = "pvpHall"
    private static let frameMaxHeightShare: CGFloat = 0.45
    private static let formMaxWidth: CGFloat = 640
    private static let stubBarGap: CGFloat = 32

    init(match: PvPMatchScreen?, reveal: PvPRevealScreen?, final: PvPFinalScreen? = nil, isDuel: Bool, mediaType: MediaType,
         mediaFacade: MediaFacadeProtocol, onGuess: @escaping (MediaItem?, String) -> Void, onSkip: @escaping () -> Void,
         onAction: @escaping (PvPAction.Kind) -> Void = { _ in }, extraBots: Int = 0) {
        self.extraBots = extraBots
        self.match = match
        self.reveal = reveal
        self.final = final
        self.onAction = onAction
        self.isDuel = isDuel
        self.mediaType = mediaType
        self.mediaFacade = mediaFacade
        self.onGuess = onGuess
        self.onSkip = onSkip
        _search = StateObject(wrappedValue: PvPAnswerSearch(mediaFacade: mediaFacade))
        _lastMatch = State(initialValue: match)
    }

    /// The film being played, or the one whose results are on screen.
    private var screen: PvPMatchScreen? { match ?? lastMatch }

    // MARK: Frames

    private var frameURLs: [URL] {
        (screen?.frames ?? []).compactMap { PvPImageLinks.frame($0.path) }
    }

    private var displayedIndex: Int? {
        guard let screen, let shown = screen.shownFrame else { return nil }
        guard let viewedFrame, viewedFrame <= screen.viewableFrame ?? shown else { return shown }
        return viewedFrame
    }

    private var displayedURL: URL? {
        guard reveal == nil, final == nil else { return nil }
        return displayedIndex.flatMap { frameURLs[safe: $0] }
    }

    private var isFrameWaiting: Bool {
        guard reveal == nil, final == nil, let stage = match?.stage else { return false }
        switch stage {
        case .picking, .preparing, .waiting: return true
        case .playing: return displayedURL != nil && !frames.hasPresentedFrame
        case .countdown, .watching: return false
        }
    }

    // MARK: Screen

    private var screenScene: PvPScreenScene? {
        if let final { return .final(final) }
        if let reveal { return .results(reveal) }
        guard let match else { return nil }
        let title = match.filmTotal.map { "Фильм \(match.filmNumber) из \($0)" } ?? "Фильм \(match.filmNumber)"
        if let resume = match.resumeIn {
            return .countdown(PvPCountdownScene(value: resume, film: match.filmNumber, title: title,
                                                detail: "Продолжаем", isResume: true))
        }
        if case let .countdown(value) = match.stage {
            return .countdown(PvPCountdownScene(value: value, film: match.filmNumber, title: title, detail: match.stageText))
        }
        return nil
    }

    private var showsScreenScene: Bool { screenScene != nil && canvas.picture != nil }

    private var hallLight: HallFrameSample { showsScreenScene ? canvas.light : frames.hallLight }
    private var hallPicture: HallPicture? { showsScreenScene ? canvas.picture : frames.picture }
    private var isProtected: Bool { isScreenProtected && reveal == nil && match?.isProtected == true }

    // MARK: Layout

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
        let preferred = min(frameWidth > 0 ? frameWidth : window.size.width, Self.formMaxWidth)
        return min(window.size.width, max(preferred, stubWidth + barInset * 2))
    }

    private var suggestionsMaxHeight: CGFloat {
        AnswerBarLayout.suggestionsMaxHeight(measuredBarBottom: highestBarBottom > 0 ? highestBarBottom : barBottom,
                                             fullHeight: fullHeight, homeIndicatorInset: homeIndicatorInset)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            FrameView(maxWidth: frameMaxWidth)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frameHeight = $0 }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    frameWidth = width
                    frames.displayPixelWidth = width * displayScale
                    canvas.pixelWidth = width * displayScale
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).midX } action: { frameMidX = $0 }
                .overlay { waitingCaption }
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
        .overlay(alignment: .topLeading) { audience }
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    fullHeight = $0
                    highestBarBottom = 0
                }
                .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .bottom) { bottomBar }
        .overlay(alignment: .bottom) {
            if let final {
                PvPFinalBar(screen: final, onAction: onAction)
                    .padding(.bottom, AnswerBarLayout.restingInset - homeIndicatorInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: final != nil)
        .background {
            if frameHeight > 0 {
                RoundBackground(light: hallLight, frameHeight: frameHeight, frameMidX: frameMidX,
                                picture: hallPicture, isWaiting: isFrameWaiting && hallPicture == nil, phone: phone,
                                isProtected: isProtected, showsCaptureBanner: isProtected && frames.hasPresentedFrame,
                                coordinateSpace: Self.space)
            }
        }
        .coordinateSpace(.named(Self.space))
        .background(WindowReader(reference: windowReference))
        .gesture(
            DragGesture().onChanged { value in
                guard value.translation.height > 20, isAnswerFocused else { return }
                DispatchQueue.main.async { AnswerBarLayout.resignKeyboard() }
            }
        )
        .onChange(of: match) { _, new in if let new { lastMatch = new } }
        .onChange(of: screenScene, initial: true) { _, scene in
            canvas.scene = scene
            if scene == nil { canvas.clear() }
        }
        .task(id: screenScene?.key) {
            guard screenScene != nil else { return }
            await canvas.run()
        }
        .task(id: reveal?.source) { await loadDetails() }
        .onChange(of: search.hasSearched) { _, _ in pendingAnimatedHeightCatchUp = true }
        .onChange(of: search.results) { _, _ in pendingAnimatedHeightCatchUp = true }
        .task(id: PvPFrameRequest(url: displayedURL, isWaiting: isFrameWaiting)) {
            await frames.show(displayedURL, isRoundLoading: isFrameWaiting)
        }
        .task(id: frameURLs) { await frames.preload(frameURLs) }
        .onChange(of: screen?.shownFrame) { _, _ in viewedFrame = nil }
        .onChange(of: screen?.filmNumber) { _, _ in
            ticketSeed = FlipTear.randomSeed()
            details = nil
            search.reset()
        }
        .onChange(of: match?.input.feedback) { _, feedback in
            guard let feedback, !feedback.correct else { return }
            Haptics.shared.play(.answerWrong)
        }
        .onChange(of: final?.tone) { _, tone in
            switch tone {
            case .win?: Haptics.shared.play(.answerCorrect)
            case .loss?: Haptics.shared.play(.answerWrong)
            case .draw?, .neutral?: Haptics.shared.play(.stamp)
            case nil: break
            }
        }
        .onChange(of: match?.stage) { old, new in
            if case .countdown = new { Haptics.shared.play(.tabBreak) }
            if new == .playing, old != .playing { Haptics.shared.play(.stamp) }
        }
        .onChange(of: screen?.rivals ?? []) { old, new in trackMisses(old: old, new: new) }
        .onChange(of: isFormVisible) { _, visible in
            if !visible { isAnswerFocused = false }
        }
        .onChange(of: isAnswerFocused) { _, focused in
            if focused { phone.stow() } else { phone.unstow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardHeight = AnswerBarLayout.dockedKeyboardHeight(screenFrame: frame, in: windowReference.window)
            keyboardLift = AnswerBarLayout.keyboardLift(forHeight: keyboardHeight)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            keyboardHeight = 0
            withAnimation(ResultStubPeek.keyboardSettleAnimation) { keyboardLift = 0 }
        }
    }

    // MARK: Waiting caption

    /// While frames load the screen keeps the hall spinner; the caption explains the wait.
    @ViewBuilder
    private var waitingCaption: some View {
        if reveal == nil, screenScene == nil, let match, match.stage != .playing, let text = match.stageText {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 18)
                .transition(.opacity)
        }
    }

    // MARK: Audience

    /// Rival avatars sit on the seats in front of you. They live above the Metal hall and the phone,
    /// so the phone's zoomed viewfinder never shows or covers them.
    @ViewBuilder
    private var audience: some View {
        if let screen, frameHeight > 0 {
            let rivals = Array((screen.rivals + Self.bots(extraBots, frameCount: max(screen.frames.count, 6))).prefix(isDuel ? 1 : 7))
            let seats = PvPSeatLayout.seats(count: rivals.count, isDuel: isDuel, frameHeight: frameHeight,
                                            frameMidX: frameMidX, width: window.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(rivals, seats)), id: \.0.id) { rival, seat in
                    PvPSeatAvatar(avatar: rival.avatar, ring: PvPRingState.rival(rival, isDuel: isDuel),
                                  size: seat.size, missToken: missTokens[rival.uid] ?? 0,
                                  frames: isDuel ? duelFrames(rival) : nil)
                        .position(seat.center)
                        .accessibilityLabel(rival.name)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
        }
    }

    private static func bots(_ count: Int, frameCount: Int) -> [PvPRivalRow] {
        let icons = ["popcorn", "clapper", "masks", "star", "projector", "film", "ticket"]
        let colors = ["orange", "blue", "purple", "pink", "teal", "indigo", "green"]
        return (0..<max(0, count)).map { index in
            let tone: PvPRivalRow.Tone = [.thinking, .solved, .failed, .thinking][index % 4]
            return PvPRivalRow(uid: "bot-\(index)", name: "Бот \(index + 1)",
                               avatar: PvPAvatar(icon: icons[index % icons.count], color: colors[index % colors.count]),
                               frame: 1 + index % frameCount, frameCount: frameCount, status: "", tone: tone,
                               isAway: index == 5, health: 1 - Double(index) * 0.12)
        }
    }

    private func duelFrames(_ rival: PvPRivalRow) -> (count: Int, misses: Int, solvedAt: Int?) {
        let ring = PvPRingState.rival(rival, isDuel: false)
        guard case let .frames(count, misses, solvedAt) = ring.kind else { return (rival.frameCount, 0, nil) }
        return (count, misses, solvedAt)
    }

    private func trackMisses(old: [PvPRivalRow], new: [PvPRivalRow]) {
        let before = Dictionary(old.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        for rival in new {
            guard let previous = before[rival.uid] else { continue }
            let missed = (rival.tone == .thinking && rival.frame > previous.frame && previous.frame > 0)
                || (rival.tone == .failed && previous.tone == .thinking)
            if missed { missTokens[rival.uid, default: 0] += 1 }
        }
    }

    // MARK: Answer form and stub

    private var isFormVisible: Bool {
        guard reveal == nil, final == nil, let match, match.stage == .playing else { return false }
        return match.input.isEnabled || match.input.isSending
    }

    private var isFieldLocked: Bool {
        guard let match else { return true }
        return !match.input.isEnabled && !match.input.isSending
    }

    private var bottomBar: some View {
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
                AnswerBarActionShape(progress: 0, width: proxy.size.width, isBlocked: match?.input.isEnabled != true,
                                     isTransitioning: false, onSubmit: submit, onNewGame: {})
            }
            .frame(height: suggestionRowHeight)
        }
        .opacity(isFormVisible ? 1 : 0)
        .scaleEffect(isFormVisible ? 1 : 0.92, anchor: .bottom)
        .allowsHitTesting(isFormVisible)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).maxY } action: {
            barBottom = $0
            highestBarBottom = highestBarBottom > 0 ? min(highestBarBottom, $0) : $0
        }
        .background(alignment: .bottom) { stubAnchor }
        .padding(.horizontal, barInset)
        .frame(maxWidth: formOuterWidth)
        .padding(.bottom, barBottomInset)
        .animation(.smooth(duration: 0.25), value: isAnswerFocused)
        .animation(reduceMotion ? nil : .smooth, value: isFormVisible)
        .disabled(isFieldLocked)
    }

    private var stubAnchor: some View {
        Color.clear
            .frame(height: 0)
            .overlay(alignment: .bottom) { resultStub }
            .geometryGroup()
    }

    private var showsStub: Bool {
        guard final == nil, let screen else { return false }
        if reveal != nil { return true }
        switch screen.stage {
        case .picking, .preparing, .waiting: return false
        case .countdown, .playing, .watching: return true
        }
    }

    @ViewBuilder
    private var resultStub: some View {
        if showsStub, let screen {
            ResultStubPeek(placement: stubPlacement,
                           item: stubItem(screen),
                           mediaType: mediaType,
                           mode: .pvp,
                           details: reveal == nil ? nil : details,
                           outcome: outcome,
                           attemptsMade: attempts(screen),
                           revealedCount: revealedCount(screen),
                           currentFrame: reveal == nil ? displayedIndex ?? 0 : 0,
                           hallLight: hallLight.mean,
                           recordingLight: isProtected ? CaptureWarningBanner.hallLight.mean : nil,
                           frameCount: max(screen.frames.count, 1),
                           filters: MediaFilters(),
                           genreNames: [],
                           isTucked: outcome == nil && isFormVisible && answerBarHeight > suggestionRowHeight + 1,
                           keyboardLift: keyboardLift,
                           restOffset: stubRestOffset,
                           formWidth: formOuterWidth - barInset * 2,
                           ticketSeed: FlipTear.seed(ticket: ticketSeed, round: screen.filmNumber),
                           header: header(screen),
                           settled: reveal == nil ? settled(screen) : nil)
                .offset(y: outcome == nil && !isFormVisible ? suggestionRowHeight : 0)
                .animation(reduceMotion ? nil : .smooth, value: isFormVisible)
                .id(screen.filmNumber)
                .transition(.asymmetric(insertion: .identity, removal: .offset(x: window.size.width)))
        }
    }

    private var outcome: RoundOutcome? {
        guard let reveal else { return nil }
        return reveal.solvedAtFrame == nil ? .incorrect : .correct
    }

    private func settled(_ screen: PvPMatchScreen) -> RoundOutcome? {
        switch screen.status?.tone {
        case .solved?: .correct
        case .failed?: .incorrect
        default: nil
        }
    }

    private func attempts(_ screen: PvPMatchScreen) -> Int {
        if let reveal { return reveal.solvedAtFrame ?? screen.frames.count }
        guard let shown = screen.shownFrame else { return 0 }
        switch settled(screen) {
        case .correct?: return shown + 1
        case .incorrect?: return screen.frames.count
        case nil: return shown
        }
    }

    private func revealedCount(_ screen: PvPMatchScreen) -> Int {
        reveal != nil ? screen.frames.count : (screen.shownFrame ?? -1) + 1
    }

    private func stubItem(_ screen: PvPMatchScreen) -> MediaItem {
        guard let answer = reveal?.source else {
            return MediaItem(id: -screen.filmNumber, mediaType: mediaType, title: "???", originalTitle: "???",
                             releaseDate: nil, overview: nil)
        }
        return MediaItem(id: answer.tmdbId, mediaType: answer.mediaType, title: answer.title,
                         originalTitle: answer.originalTitle, releaseDate: answer.year.map { "\($0)" }, overview: nil)
    }

    private func header(_ screen: PvPMatchScreen) -> ResultStubHeader {
        let badge: ResultStubHeader.Badge?
        if let duel = screen.duel {
            badge = .health(hp: duel.you.hp, maxHP: duel.you.maxHP)
        } else {
            badge = screen.yourScore.map { .score(PvPScreenText.number($0)) }
        }
        if let reveal {
            return ResultStubHeader(timer: reveal.nextTimer?.text ?? "0:00", isFrozen: reveal.nextTimer?.isFrozen == true,
                                    badge: badge)
        }
        let timer = screen.timer
        return ResultStubHeader(timer: timer?.text ?? "–:––", isUrgent: timer?.isUrgent == true,
                                isFrozen: timer?.isFrozen == true, badge: badge)
    }

    private var stubRestOffset: CGFloat {
        let restingBarTop = fullHeight - (AnswerBarLayout.restingInset - homeIndicatorInset) - suggestionRowHeight
        let gap = restingBarTop - frameHeight
        let stubHeight = TicketStubMetrics.height(width: stubWidth, edgeStyle: TicketEdgeStyle(hasScallops: hasScallops))
        let restingStubTop = frameHeight + max(0, gap - stubHeight - Self.stubBarGap)
        return restingStubTop + stubHeight - restingBarTop - suggestionRowHeight
    }

    private func loadDetails() async {
        guard let answer = reveal?.source else { return }
        details = try? await mediaFacade.fetchDetails(mediaType: answer.mediaType, id: answer.tmdbId)
    }

    // MARK: Actions

    private func showFrame(by step: Int) {
        guard reveal == nil, let screen, let shown = screen.shownFrame else { return }
        let next = (displayedIndex ?? shown) + step
        guard (0...(screen.viewableFrame ?? shown)).contains(next) else { return }
        viewedFrame = next
    }

    private func updateAnswerBarHeight(_ newHeight: CGFloat) {
        if pendingAnimatedHeightCatchUp {
            pendingAnimatedHeightCatchUp = false
            withAnimation(.snappy) { answerBarHeight = newHeight }
        } else {
            answerBarHeight = newHeight
        }
    }

    private func submit() {
        guard match?.input.isEnabled == true else { return }
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

#if DEBUG
/// Any match, reveal or final fixture rendered in the hall, as it looks inside the room.
private struct PvPHallPreview: View {
    let state: PvPMatchState

    var body: some View {
        let screen = PvPPreview.screen(state)
        NavigationStack {
            Group {
                switch screen.content {
                case let .match(match):
                    hall(match: match)
                case let .reveal(reveal):
                    hall(reveal: reveal)
                case let .final(final):
                    hall(final: final)
                default:
                    Text("Не зал")
                }
            }
            .navigationTitle(screen.chrome.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .providesWindowGeometry()
        .environment(\.resultStubWidth, TicketStyle.referenceWidth)
        .preferredColorScheme(.dark)
    }

    private func hall(match: PvPMatchScreen? = nil, reveal: PvPRevealScreen? = nil, final: PvPFinalScreen? = nil) -> some View {
        PvPHallView(match: match, reveal: reveal, final: final, isDuel: state.kind == .duel, mediaType: .movie,
                    mediaFacade: PreviewMediaFacade(), onGuess: { _, _ in }, onSkip: {})
    }
}

#Preview("Подбор фильмов") { PvPHallPreview(state: PvPMatchFixtures.loading) }
#Preview("Загрузка кадров") { PvPHallPreview(state: PvPMatchFixtures.preparing) }
#Preview("Ждём остальных") { PvPHallPreview(state: PvPMatchFixtures.preparedWaiting) }
#Preview("Отсчёт") { PvPHallPreview(state: PvPMatchFixtures.countdown) }
#Preview("Игра, думаю") { PvPHallPreview(state: PvPMatchFixtures.playingThinking) }
#Preview("Игра, отправляю") { PvPHallPreview(state: PvPMatchFixtures.playingAnswering) }
#Preview("Игра, соперник угадал") { PvPHallPreview(state: PvPMatchFixtures.playingRivalSolved) }
#Preview("Игра, дедлайн") { PvPHallPreview(state: PvPMatchFixtures.playingDeadline) }
#Preview("Игра, угадал и жду") { PvPHallPreview(state: PvPMatchFixtures.playingSolved) }
#Preview("Игра, зритель") { PvPHallPreview(state: PvPMatchFixtures.playingSpectator) }
#Preview("После паузы") { PvPHallPreview(state: PvPMatchFixtures.resuming) }
#Preview("Итоги фильма, комната") { PvPHallPreview(state: PvPMatchFixtures.revealRoom) }
#Preview("Финал, комната") { PvPHallPreview(state: PvPMatchFixtures.finishedRoom) }
#Preview("Финал, комната, хост") { PvPHallPreview(state: PvPMatchFixtures.finishedRoomWinner) }
#Preview("Дуэль, загрузка") { PvPHallPreview(state: PvPMatchFixtures.duelPreparing) }
#Preview("Дуэль, игра") { PvPHallPreview(state: PvPMatchFixtures.duelPlaying) }
#Preview("Дуэль, соперник свернул") { PvPHallPreview(state: PvPMatchFixtures.rivalAway) }
#Preview("Дуэль, итоги фильма") { PvPHallPreview(state: PvPMatchFixtures.revealDuel) }
#Preview("Дуэль, победа") { PvPHallPreview(state: PvPMatchFixtures.finishedVictory) }
#Preview("Дуэль, поражение") { PvPHallPreview(state: PvPMatchFixtures.finishedDefeat) }
#Preview("Дуэль, ничья") { PvPHallPreview(state: PvPMatchFixtures.finishedDraw) }

/// The audience on its own, over a black hall, for every ring state and seat count.
private struct PvPAudiencePreview: View {
    let count: Int
    let isDuel: Bool

    var body: some View {
        GeometryReader { proxy in
            let frameHeight = proxy.size.width * 9 / 16
            let seats = PvPSeatLayout.seats(count: count, isDuel: isDuel, frameHeight: frameHeight,
                                            frameMidX: proxy.size.width / 2, width: proxy.size.width)
            let avatars = ["clapper", "projector", "masks", "popcorn", "star", "film", "ticket"]
            let colors = ["blue", "teal", "purple", "orange", "pink", "indigo", "green"]
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.white.opacity(0.08)).frame(height: frameHeight)
                ForEach(Array(seats.enumerated()), id: \.offset) { index, seat in
                    VStack(spacing: 2) {
                        PvPSeatAvatar(avatar: PvPAvatar(icon: avatars[index], color: colors[index]),
                                      ring: isDuel ? PvPRingState(kind: .health(0.6))
                                                   : PvPRingState(kind: .frames(count: 6, misses: index % 3, solvedAt: index == 2 ? 3 : nil),
                                                                  isSolved: index == 2),
                                      size: seat.size)
                        Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.white)
                    }
                    .position(seat.center)
                }
            }
        }
        .background(.black)
    }
}

#Preview("Места: 7 соперников") { PvPAudiencePreview(count: 7, isDuel: false) }
#Preview("Места: 3 соперника") { PvPAudiencePreview(count: 3, isDuel: false) }
#Preview("Места: дуэль") { PvPAudiencePreview(count: 1, isDuel: true) }
#endif
