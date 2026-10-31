//
//  PvPRevealView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPRevealView: View {
    let screen: PvPRevealScreen

    var body: some View {
        PvPPage {
            PvPKicker(text: screen.title)
            PvPCard {
                VStack(alignment: .leading, spacing: 14) {
                    PvPAnswerCardView(answer: screen.answer)
                    Text(screen.verdict)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(screen.isSolved ? PvPStyle.hit : PvPStyle.miss)
                }
            }
            if let duel = screen.duel {
                PvPCard {
                    VStack(spacing: 12) {
                        PvPDuelBarsView(bars: duel)
                        if let line = screen.damageLine {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !screen.results.isEmpty {
                PvPKicker(text: "Этот фильм")
                PvPResultsView(rows: screen.results)
            }
            if !screen.standings.isEmpty {
                PvPKicker(text: "Таблица")
                PvPStandingsView(rows: screen.standings)
            }
        }
        .safeAreaInset(edge: .bottom) { nextBar }
        .onAppear { Haptics.shared.play(screen.isSolved ? .answerCorrect : .answerWrong) }
    }

    @ViewBuilder
    private var nextBar: some View {
        if let next = screen.next, let timer = screen.nextTimer {
            HStack(spacing: 8) {
                Text(next)
                    .font(.subheadline.weight(.semibold))
                Text(timer.text)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: timer.text)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 12)
        }
    }
}

#if DEBUG
private struct PvPRevealPreview: View {
    let state: PvPMatchState

    var body: some View {
        NavigationStack {
            if let reveal = PvPPreview.reveal(state) {
                PvPRevealView(screen: reveal)
                    .navigationTitle(state.kind == .duel ? "Дуэль" : "Комната")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Разбор комнаты") { PvPRevealPreview(state: PvPMatchFixtures.revealRoom) }
#Preview("Разбор дуэли") { PvPRevealPreview(state: PvPMatchFixtures.revealDuel) }

private func missedReveal() -> PvPMatchState {
    var state = PvPMatchFixtures.revealRoom
    state.you = PvPMatchFixtures.third
    state.players = state.players.map { player in
        var player = player
        player.isYou = player.uid == PvPMatchFixtures.third
        return player
    }
    return state
}

#Preview("Разбор, не угадал") { PvPRevealPreview(state: missedReveal()) }
#endif
