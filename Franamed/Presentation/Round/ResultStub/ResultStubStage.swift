//
//  ResultStubStage.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import SwiftUI
import UIKit

struct ResultStubStage: View {
    let item: MediaItem
    let mediaType: MediaType
    let details: MediaDetails?
    let outcome: RoundOutcome
    let attemptsUsed: Int
    let frameCount: Int
    let filters: MediaFilters
    let genreNames: [String]
    let topInset: CGFloat
    let restingOffset: CGFloat

    @State private var playedAt = Date.now
    @State private var reveal: CGFloat = 0
    @State private var shake: CGFloat = 0
    @State private var webSearch: WebSearchLink?

    private static let arrival = Spring(response: 0.5, dampingRatio: 0.72)
    private static let slideDuration = 0.42
    private static let firstContact: TimeInterval = {
        var time: TimeInterval = 0
        while time < 2, arrival.value(target: 1.0, time: time) < 1 { time += 0.001 }
        return time
    }()

    private struct FacesID: Hashable {
        let content: ResultStubContent
        let genreNames: [String]
    }

    private var content: ResultStubContent {
        ResultStubContent(item: item, mediaType: mediaType, details: details, outcome: outcome,
                          attemptsUsed: attemptsUsed, frameCount: frameCount, playedAt: playedAt)
    }

    private var travel: CGFloat { restingOffset + ResultStubMetrics.height }

    var body: some View {
        let content = content

        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)

            Color.clear
                .frame(width: ResultStubMetrics.width, height: travel)
                .overlay(alignment: .bottom) {
                    TicketFlipView(size: CGSize(width: ResultStubMetrics.width, height: ResultStubMetrics.height),
                                   contentID: FacesID(content: content, genreNames: genreNames),
                                   menuItems: menuItems(content)) {
                        ResultStubFront(content: content)
                    } back: {
                        ResultStubSetupBack(mediaType: mediaType, filters: filters,
                                            frameCount: frameCount, genreNames: genreNames)
                    }
                    .offset(y: -travel * (1 - reveal))
                    .modifier(StubShake(animatableData: shake))
                }
                .mask(alignment: .top) {
                    Rectangle()
                        .padding(.horizontal, -FlipLook.canvasPadding)
                        .padding(.bottom, -FlipLook.canvasPadding)
                }

            Spacer(minLength: 0)
        }
        .sheet(item: $webSearch) { link in
            SafariSheet(url: link.url).ignoresSafeArea()
        }
        .task { await arrive() }
    }

    private func arrive() async {
        if outcome == .correct {
            withAnimation(.spring(Self.arrival)) { reveal = 1 }
            try? await Task.sleep(for: .seconds(Self.firstContact))
            guard !Task.isCancelled else { return }
            Haptics.shared.play(.answerCorrect)
        } else {
            withAnimation(.easeOut(duration: Self.slideDuration)) { reveal = 1 }
            try? await Task.sleep(for: .seconds(Self.slideDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: StubShake.duration)) { shake = 1 }
            Haptics.shared.play(.answerWrong)
        }
    }

    private func menuItems(_ content: ResultStubContent) -> [StubMenuItem] {
        [
            StubMenuItem(title: "Скопировать название", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = content.title
            },
            StubMenuItem(title: "Загуглить", systemImage: "magnifyingglass") {
                webSearch = WebSearchLink(query: searchQuery(content))
            }
        ]
    }

    private func searchQuery(_ content: ResultStubContent) -> String {
        guard let year = item.releaseDate?.prefix(4), !year.isEmpty else { return content.title }
        return "\(content.title) \(year)"
    }
}
