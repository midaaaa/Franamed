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
    let restOffset: CGFloat
    let formWidth: CGFloat

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @State private var playedAt = Date.now
    @State private var reveal: CGFloat = 0
    @State private var shake: CGFloat = 0
    @State private var hasLanded = false
    @State private var hasEntered = false
    @State private var drop: CGFloat = 0
    @State private var follow: CGFloat = 0
    @State private var webSearch: WebSearchLink?

    private static let peekHeight: CGFloat = 33
    private static let tilt: Double = 32
    private static let perspective: CGFloat = 0.5
    private static let flightSheen: Float = 0.4
    private static let screenEdgeGap: CGFloat = 48
    private static let entryDelay = Duration.milliseconds(30)
    private static let keyboardAnimation = Animation.spring(response: 0.3, dampingFraction: 1)
    static let tuckAnimation = Animation.snappy
    static let keyboardSettleAnimation = Animation.smooth
    static let exitAnimation = Animation.easeIn(duration: 0.3)

    private struct FacesID: Hashable {
        let content: ResultStubContent
        let genreNames: [String]
        let hidesDetails: Bool
    }

    private var size: CGSize {
        CGSize(width: ResultStubMetrics.width,
               height: ResultStubMetrics.height(edgeStyle: TicketEdgeStyle(hasScallops: hasScallops)))
    }

    private var hidesDetails: Bool { outcome == nil }

    private var tilt: Double { Self.tilt * Double(1 - reveal) }

    private var isHidden: Bool { isTucked || !hasEntered }

    private var hiddenOffset: CGFloat {
        guard isHidden else { return size.height - suggestionRowHeight - Self.peekHeight }
        switch placement {
        case .behindForm: return size.height + Self.screenEdgeGap + keyboardLift
        case .clippedByForm: return size.height - suggestionRowHeight
        }
    }

    private var offset: CGFloat {
        hiddenOffset + (restOffset - hiddenOffset) * reveal + drop * (reveal - follow)
    }

    private var content: ResultStubContent {
        ResultStubContent(item: item, mediaType: mediaType, details: details, outcome: outcome,
                          attemptsUsed: max(attemptsMade, 1), playedAt: playedAt,
                          marks: ResultStubMark.live(frameCount: frameCount, attemptsMade: attemptsMade,
                                                     revealedCount: revealedCount, outcome: outcome),
                          currentFrame: currentFrame)
    }

    var body: some View {
        let content = content

        FlipView(size: size,
                 contentID: FacesID(content: content, genreNames: genreNames, hidesDetails: hidesDetails),
                 menuItems: content.menuItems { webSearch = WebSearchLink(query: $0) }) {
            ResultStubFront(content: content, hidesDetails: hidesDetails)
        } back: {
            ResultStubSetupBack(card: TicketCard(mediaType: mediaType, posterPath: nil, mode: mode),
                                setup: RoundSetup(filters: filters, frameCount: frameCount),
                                genreNames: genreNames)
        }
        .modifier(ResultStubTiltLight(animatableData: tilt, maxTilt: Self.tilt, hallMean: hallLight,
                                       recordingMean: recordingLight,
                                       sheenScale: hasLanded ? 1 : Self.flightSheen))
        .modifier(ResultStubShake(animatableData: shake))
        .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), anchor: .top,
                          perspective: Self.perspective)
        .allowsHitTesting(outcome != nil && hasLanded)
        .offset(y: offset)
        .modifier(FormClip(isActive: placement == .clippedByForm, formWidth: formWidth))
        .animation(Self.tuckAnimation, value: isHidden)
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
            await arrive(outcome)
        }
        .onChange(of: keyboardLift, initial: true) { _, lift in
            guard outcome == nil else { return }
            drop = lift
        }
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
