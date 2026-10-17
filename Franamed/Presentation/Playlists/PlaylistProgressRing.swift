//
//  PlaylistProgressRing.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct PlaylistProgressRing: View {
    let playlist: PlaylistDetail
    var lineWidth: CGFloat = 6

    private var total: Int { playlist.availableCount }
    private var correct: Int { playlist.playableItems.filter { $0.wasCorrect == true }.count }
    private var missed: Int { playlist.playableItems.filter { $0.state == .completed && $0.wasCorrect == false }.count }
    private var isPerfect: Bool { playlist.completion == .perfect }

    var body: some View {
        ZStack {
            Circle().stroke(.fill.tertiary, lineWidth: lineWidth)
            arc(from: 0, to: share(correct), color: isPerfect ? PlaylistStyle.gold : PlaylistStyle.hit)
            arc(from: share(correct), to: share(correct + missed), color: PlaylistStyle.miss)
            count
                .padding(lineWidth + 4)
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if playlist.completion != .inProgress {
                PlaylistSealStamp(isGold: isPerfect)
                    .scaleEffect(0.6)
                    .offset(x: 8, y: 8)
            }
        }
    }

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(correct)")
                .font(.system(.title3, design: .monospaced).weight(.bold))
            Text("/\(total)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isPerfect ? PlaylistStyle.gold : .primary)
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
