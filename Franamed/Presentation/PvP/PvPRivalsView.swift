//
//  PvPRivalsView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPRivalsView: View {
    let rivals: [PvPRivalRow]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(rivals) { rival in
                PvPRivalBadge(rival: rival)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy, value: rivals)
    }
}

struct PvPRivalBadge: View {
    let rival: PvPRivalRow

    private static let avatarSize: CGFloat = 30

    var body: some View {
        VStack(spacing: 5) {
            PvPAvatarView(avatar: rival.avatar, size: Self.avatarSize, isDimmed: rival.isAway || rival.tone == .out)
                .padding(2)
                .overlay {
                    Circle().strokeBorder(ringColor, lineWidth: 2)
                }
                .overlay(alignment: .bottomTrailing) {
                    if rival.tone == .solved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white, PvPStyle.hit)
                            .offset(x: 3, y: 3)
                    }
                }
            PvPFramePips(count: rival.frameCount, frame: rival.frame, tone: rival.tone, pipWidth: 5)
            Text(rival.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: Self.avatarSize + 12)
        }
    }

    private var ringColor: Color {
        switch rival.tone {
        case .solved: PvPStyle.hit
        case .failed: PvPStyle.miss
        case .thinking: .white.opacity(0.35)
        case .out: .clear
        }
    }
}

struct PvPFramePips: View {
    let count: Int
    let frame: Int
    let tone: PvPRivalRow.Tone
    var pipWidth: CGFloat = 12

    var body: some View {
        HStack(spacing: pipWidth < 12 ? 2 : 3) {
            ForEach(0..<max(count, 0), id: \.self) { index in
                Capsule()
                    .fill(color(index))
                    .frame(width: pipWidth, height: pipWidth < 12 ? 3 : 4)
            }
        }
    }

    private func color(_ index: Int) -> Color {
        let current = frame - 1
        switch tone {
        case .out: return .white.opacity(0.12)
        case .failed: return PvPStyle.miss
        case .solved: return index < current ? PvPStyle.miss : index == current ? PvPStyle.hit : .white.opacity(0.12)
        case .thinking: return index < current ? PvPStyle.miss : index == current ? .white : .white.opacity(0.12)
        }
    }
}

#if DEBUG
#Preview("Соперники в комнате") {
    if let match = PvPPreview.match(PvPMatchFixtures.playingDeadline) {
        PvPRivalsView(rivals: match.rivals)
            .padding()
            .preferredColorScheme(.dark)
    }
}

#Preview("Соперник в дуэли") {
    if let match = PvPPreview.match(PvPMatchFixtures.duelPlaying) {
        PvPRivalsView(rivals: match.rivals)
            .padding()
            .preferredColorScheme(.dark)
    }
}

#Preview("Отметки кадров") {
    VStack(alignment: .leading, spacing: 12) {
        PvPFramePips(count: 6, frame: 1, tone: .thinking)
        PvPFramePips(count: 6, frame: 3, tone: .thinking)
        PvPFramePips(count: 6, frame: 2, tone: .solved)
        PvPFramePips(count: 6, frame: 6, tone: .failed)
        PvPFramePips(count: 4, frame: 0, tone: .out)
    }
    .padding()
    .preferredColorScheme(.dark)
}
#endif
