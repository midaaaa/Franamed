//
//  ResultStubPeek.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 26.09.2026.
//

import SwiftUI

enum ResultStubPlacement: String {
    case behindForm, clippedByForm
}

struct ResultStubPeek: View {
    let placement: ResultStubPlacement
    let item: MediaItem
    let mediaType: MediaType
    let mode: TicketGameMode
    let details: MediaDetails?
    let outcome: RoundOutcome?
    let attemptsMade: Int
    let revealedCount: Int
    let currentFrame: Int
    let hallLight: SIMD3<Float>
    let recordingLight: SIMD3<Float>?
    let frameCount: Int
    let filters: MediaFilters
    let genreNames: [String]
    let isTucked: Bool
    let keyboardLift: CGFloat
    var foldTop: CGFloat?
    let restOffset: CGFloat
    let formWidth: CGFloat
    var playlist: PlaylistTicket?
    let ticketSeed: UInt64
    var onBackShown: () -> Void = {}
    var isLifted = false
    var onShare: ((ResultStubContent, ShareLaunch) -> Void)?

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @Environment(\.resultStubWidth) private var stubWidth
    @State private var playedAt = Date.now
    @State private var reveal: CGFloat = 0
    @State private var shake: CGFloat = 0
    @State private var hasLanded = false
    @State private var hasEntered = false
    @State private var drop: CGFloat = 0
    @State private var follow: CGFloat = 0
    @State private var webSearch: WebSearchLink?
    @State private var lastLifeShake: CGFloat = 0
    @State private var lastLifeStrength: CGFloat = 1
    @State private var isFrontVisible = true
    @State private var globalFrame = CGRect.zero
    @State private var snapshotter = FlipSnapshotter()

    private static let peekHeight: CGFloat = 33
    private static let tilt: Double = 32
    private static let perspective: CGFloat = 0.5
    private static let flightSheen: Float = 0.4
    private static let screenEdgeGap: CGFloat = 48
    private static let entryDelay = Duration.milliseconds(30)
    private static let keyboardAnimation = Animation.spring(response: 0.3, dampingFraction: 1)
    private static let lastLifeFadeDuration = 0.15
    static let tuckAnimation = Animation.snappy
    static let keyboardSettleAnimation = Animation.smooth
    static let exitAnimation = Animation.easeIn(duration: 0.3)

    private struct FacesID: Hashable {
        let content: ResultStubContent
        let genreNames: [String]
        let hidesDetails: Bool
        let playlist: PlaylistTicket?
    }

    static func peekHeight(stubWidth: CGFloat) -> CGFloat {
        peekHeight * TicketStyle.zoom(forWidth: stubWidth)
    }

    private var size: CGSize {
        ResultStubMetrics.size(width: stubWidth, edgeStyle: TicketEdgeStyle(hasScallops: hasScallops))
    }

    private var hidesDetails: Bool { outcome == nil }

    private var tilt: Double { Self.tilt * Double(1 - reveal) }

    private var isHidden: Bool { isTucked || !hasEntered }

    private var hiddenOffset: CGFloat {
        guard isHidden else {
            if let foldTop { return size.height + foldTop }
            return size.height - suggestionRowHeight - Self.peekHeight(stubWidth: stubWidth)
        }
        switch placement {
        case .behindForm: return size.height + Self.screenEdgeGap + keyboardLift
        case .clippedByForm: return size.height - suggestionRowHeight
        }
    }

    private var offset: CGFloat {
        hiddenOffset + (restOffset - hiddenOffset) * reveal + drop * (reveal - follow)
    }

    private var content: ResultStubContent {
        ResultStubContent(item: item, mediaType: mediaType, details: details, playedAt: playedAt,
                          progress: ResultStubProgress(frameCount: frameCount, attemptsMade: attemptsMade,
                                                       revealedCount: revealedCount, outcome: outcome,
                                                       currentFrame: currentFrame),
                          tearEdge: TearEdge(seed: tearSeed))
    }

    var body: some View {
        let content = content

        FlipView(size: size,
                 contentID: FacesID(content: content, genreNames: genreNames, hidesDetails: hidesDetails,
                                    playlist: playlist),
                 menuItems: content.menuItems(onWebSearch: { webSearch = WebSearchLink(query: $0) },
                                              onShare: shareAction(content)),
                 snapshotter: snapshotter) {
            ResultStubFront(content: content, hidesDetails: hidesDetails)
        } back: {
            ResultStubSetupBack(card: TicketCard(mediaType: mediaType, posterPath: nil, mode: mode, playlist: playlist),
                                setup: RoundSetup(filters: filters, frameCount: frameCount),
                                genreNames: genreNames, edge: content.tearEdge)
        } onFrontVisibleChange: { isFront in
            isFrontVisible = isFront
            if !isFront { onBackShown() }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { globalFrame = $0 }
        .modifier(ResultStubTiltLight(animatableData: tilt, maxTilt: Self.tilt, hallMean: hallLight,
                                       recordingMean: recordingLight,
                                       sheenScale: hasLanded ? 1 : Self.flightSheen))
        .environment(\.flipTear, tear)
        .environment(\.flipPaperCore, TicketInk.stub(for: mediaType).core)
        .modifier(ResultStubShake(progress: shake))
        .modifier(ResultStubShake(progress: lastLifeShake, strength: lastLifeStrength))
        .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), anchor: .top,
                          perspective: Self.perspective)
        .allowsHitTesting(outcome != nil && hasLanded)
        .offset(y: offset)
        .modifier(FormClip(isActive: placement == .clippedByForm, formWidth: formWidth))
        .opacity(isLifted ? 0 : 1)
        .animation(Self.tuckAnimation, value: isHidden)
        .animation(Self.tuckAnimation, value: foldTop)
        .sheet(item: $webSearch) { link in
            SafariSheet(url: link.url).ignoresSafeArea()
        }
        .task {
            try? await Task.sleep(for: Self.entryDelay)
            guard !Task.isCancelled else { return }
            hasEntered = true
        }
        .task(id: outcome) {
            guard let outcome else {
                reveal = 0
                shake = 0
                hasLanded = false
                follow = 0
                return
            }
            if drop > 0 { followKeyboard() }
            withAnimation(.easeOut(duration: Self.lastLifeFadeDuration)) { lastLifeStrength = 0 }
            await arrive(outcome)
        }
        .onChange(of: attemptsMade) { _, attempts in
            guard outcome == nil, frameCount > 1, attempts > 0,
                  FlipTear.isLastLife(misses: attempts, frameCount: frameCount) else { return }
            lastLifeShake = 0
            lastLifeStrength = 1
            withAnimation(.linear(duration: ResultStubShake.duration)) { lastLifeShake = 1 }
        }
        .onChange(of: keyboardLift, initial: true) { _, lift in
            guard outcome == nil else { return }
            drop = lift
        }
    }

    private func shareAction(_ content: ResultStubContent) -> (() -> Void)? {
        guard let onShare, outcome != nil else { return nil }
        return {
            onShare(content, ShareLaunch(snapshotter: snapshotter, source: globalFrame, startsOnBack: !isFrontVisible,
                                         stubWidth: stubWidth))
        }
    }

    private var tear: FlipTear {
        FlipTear.round(seed: tearSeed, attemptsMade: attemptsMade,
                       frameCount: frameCount, outcome: outcome, hasLanded: hasLanded)
    }

    private var tearSeed: UInt64 {
        playlist?.tearSeed(for: "\(mediaType.rawValue)_\(item.id)") ?? ticketSeed
    }

    private func followKeyboard() {
        withAnimation(Self.keyboardAnimation) { follow = 1 }
    }

    private func arrive(_ outcome: RoundOutcome) async {
        if outcome == .correct {
            withAnimation(.spring(ResultStubTiming.arrival)) { reveal = 1 }
            try? await Task.sleep(for: .seconds(ResultStubTiming.firstContact))
            guard !Task.isCancelled else { return }
            Haptics.shared.play(.answerCorrect)
            try? await Task.sleep(for: .seconds(ResultStubTiming.settleAfterContact))
        } else {
            withAnimation(.easeOut(duration: ResultStubTiming.slideDuration)) { reveal = 1 }
            try? await Task.sleep(for: .seconds(ResultStubTiming.slideDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: ResultStubShake.duration)) { shake = 1 }
            Haptics.shared.play(.answerWrong)
            try? await Task.sleep(for: .seconds(ResultStubShake.duration))
        }
        guard !Task.isCancelled else { return }
        hasLanded = true
    }
}

private struct FormClip: ViewModifier {
    let isActive: Bool
    let formWidth: CGFloat

    func body(content: Content) -> some View {
        if isActive {
            content.mask(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .frame(height: 4000)
                        .padding(.horizontal, -200)
                        .padding(.bottom, suggestionRowHeight / 2)
                    RoundedRectangle(cornerRadius: suggestionRowHeight / 2, style: .continuous)
                        .frame(width: formWidth, height: suggestionRowHeight)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
        } else {
            content
        }
    }
}
