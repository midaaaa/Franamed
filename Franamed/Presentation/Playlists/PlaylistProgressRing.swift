//
//  PlaylistProgressRing.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct PlaylistProgressRing: View {
    let total: Int
    let correct: Int
    let missed: Int
    let completion: PlaylistCompletion
    var zoom: CGFloat = 1
    var stampScale: CGFloat = 1
    var stampProgress: Double = 1
    var hasWhiteStamp = false

    @Environment(\.colorScheme) private var colorScheme

    private var lineWidth: CGFloat { 6 * zoom }
    private var isPerfect: Bool { completion == .perfect }
    private var isOnPaper: Bool { colorScheme == .light }
    private var gold: Color { isOnPaper ? PlaylistStyle.goldOnPaper : PlaylistStyle.gold }

    var body: some View {
        ZStack {
            Circle().stroke(isOnPaper ? AnyShapeStyle(PlaylistStyle.trackOnPaper) : AnyShapeStyle(.fill.tertiary), lineWidth: lineWidth)
            arc(from: 0, to: share(correct), color: isPerfect ? gold : PlaylistStyle.hit)
            arc(from: share(correct), to: share(correct + missed), color: PlaylistStyle.miss)
            count
                .padding(lineWidth + 4)
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if completion != .inProgress {
                ZStack {
                    if hasWhiteStamp && isPerfect {
                        PlaylistSealStamp()
                    }
                    PlaylistSealStamp(isGold: isPerfect, progress: stampProgress)
                }
                .scaleEffect(stampScale * zoom)
                .offset(x: 8 * zoom, y: 8 * zoom)
            }
        }
    }

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(correct)")
                .font(PlaylistStyle.scaledFont(.title3, zoom: zoom, weight: .bold, design: .monospaced))
            Text("/\(total)")
                .font(PlaylistStyle.scaledFont(.caption1, zoom: zoom, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isPerfect && !isOnPaper ? PlaylistStyle.gold : .primary)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    private func share(_ count: Int) -> CGFloat {
        total == 0 ? 0 : CGFloat(count) / CGFloat(total)
    }

    private func arc(from start: CGFloat, to end: CGFloat, color: Color) -> some View {
        Circle()
            .trim(from: start, to: end)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }
}

extension PlaylistProgressRing {
    init(playlist: PlaylistDetail, zoom: CGFloat = 1) {
        let items = playlist.playableItems
        self.init(total: playlist.availableCount,
                  correct: items.filter { $0.wasCorrect == true }.count,
                  missed: items.filter { $0.state == .completed && $0.wasCorrect == false }.count,
                  completion: playlist.completion,
                  zoom: zoom)
    }

    init(ticket: PlaylistTicket, stampScale: CGFloat) {
        self.init(total: ticket.total,
                  correct: ticket.correct,
                  missed: ticket.answered - ticket.correct,
                  completion: ticket.isFinished ? (ticket.isPerfect ? .perfect : .passed) : .inProgress,
                  stampScale: stampScale,
                  stampProgress: ticket.stampProgress,
                  hasWhiteStamp: ticket.hasWhiteStamp)
    }
}

#Preview("Кольца всех подборок") {
    PlaylistsPreview { playlists in
        ScrollView(.horizontal) {
            HStack(spacing: 24) {
                ForEach(playlists.playlists) { PlaylistProgressRing(playlist: $0) }
            }
            .frame(height: 72)
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}
