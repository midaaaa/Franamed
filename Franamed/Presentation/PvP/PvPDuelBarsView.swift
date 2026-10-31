//
//  PvPDuelBarsView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPDuelBarsView: View {
    let bars: PvPDuelBars

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                PvPHealthBarView(bar: bars.you, alignment: .leading)
                PvPHealthBarView(bar: bars.rival, alignment: .trailing)
            }
            if let multiplier = bars.multiplier {
                Text(multiplier)
                    .font(PvPStyle.kicker)
                    .tracking(1.5)
                    .foregroundStyle(PvPStyle.win)
            }
        }
    }
}

struct PvPHealthBarView: View {
    let bar: PvPHealthBar
    let alignment: HorizontalAlignment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLeading: Bool { alignment == .leading }

    private var fill: Color {
        switch bar.fraction {
        case ..<0.25: PvPStyle.miss
        case ..<0.5: PvPStyle.win
        default: PvPStyle.hit
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            HStack(spacing: 8) {
                if isLeading { PvPAvatarView(avatar: bar.avatar, size: 24) }
                Text(bar.isYou ? "Вы" : bar.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !isLeading { PvPAvatarView(avatar: bar.avatar, size: 24) }
            }
            Capsule()
                .fill(.fill.tertiary)
                .overlay(alignment: isLeading ? .leading : .trailing) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(fill)
                            .frame(width: proxy.size.width * bar.fraction)
                            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
                    }
                }
                .frame(height: 10)
                .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: bar.hp)
            HStack(spacing: 6) {
                if !isLeading, let damage = bar.damage { damageText(damage) }
                Text("\(bar.text) HP")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                if isLeading, let damage = bar.damage { damageText(damage) }
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private func damageText(_ damage: String) -> some View {
        Text(damage)
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(PvPStyle.miss)
    }
}

#if DEBUG
#Preview("HP в игре") {
    if let duel = PvPPreview.match(PvPMatchFixtures.duelPlaying)?.duel {
        PvPDuelBarsView(bars: duel)
            .padding()
            .preferredColorScheme(.dark)
    }
}

#Preview("HP с уроном") {
    if let duel = PvPPreview.reveal(PvPMatchFixtures.revealDuel)?.duel {
        PvPDuelBarsView(bars: duel)
            .padding()
            .preferredColorScheme(.dark)
    }
}

#Preview("HP, нокаут") {
    if let duel = PvPPreview.final(PvPMatchFixtures.finishedVictory)?.duel {
        PvPDuelBarsView(bars: duel)
            .padding()
            .preferredColorScheme(.dark)
    }
}
#endif
