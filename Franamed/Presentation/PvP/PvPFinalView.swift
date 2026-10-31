//
//  PvPFinalView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPFinalView: View {
    let screen: PvPFinalScreen
    let onAction: (PvPAction.Kind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    private var tint: Color {
        switch screen.tone {
        case .win: PvPStyle.win
        case .loss: PvPStyle.miss
        case .draw, .neutral: .white
        }
    }

    var body: some View {
        PvPPage {
            header
            if let duel = screen.duel {
                PvPCard { PvPDuelBarsView(bars: duel) }
            }
            PvPKicker(text: "Итоги")
            PvPStandingsView(rows: screen.standings)
            PvPKicker(text: screen.solvedLine)
            films
            ShareLink(item: screen.shareText) {
                Label("Поделиться итогом", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .onAppear {
            switch screen.tone {
            case .win: Haptics.shared.play(.answerCorrect)
            case .loss: Haptics.shared.play(.answerWrong)
            case .draw, .neutral: Haptics.shared.play(.stamp)
            }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { isShown = true }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(screen.title)
                .font(PvPStyle.largeTitle)
                .foregroundStyle(tint)
                .scaleEffect(isShown || reduceMotion ? 1 : 0.8)
                .opacity(isShown ? 1 : 0)
            Text(screen.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var films: some View {
        PvPCard(padding: 6) {
            VStack(spacing: 0) {
                ForEach(Array(screen.films.enumerated()), id: \.element.id) { index, film in
                    PvPFinalFilmRow(film: film)
                    if index < screen.films.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if screen.primary != nil || screen.hint != nil {
            VStack(spacing: 8) {
                if let hint = screen.hint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let primary = screen.primary {
                    PvPPrimaryButton(title: primary.title, isEnabled: primary.isEnabled) {
                        Haptics.shared.play(.menuSelect)
                        onAction(primary.kind)
                    }
                }
            }
            .frame(maxWidth: PvPStyle.maxWidth)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

struct PvPFinalFilmRow: View {
    let film: PvPFinalFilm

    var body: some View {
        HStack(spacing: 12) {
            CachedRemoteImage(url: PvPImageLinks.poster(film.answer.posterPath))
                .frame(width: 40, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(film.answer.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(film.yourResult)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(film.isSolved ? PvPStyle.hit : PvPStyle.miss)
                if let best = film.best {
                    Text(best)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text("\(film.number)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

#if DEBUG
private struct PvPFinalPreview: View {
    let state: PvPMatchState

    var body: some View {
        NavigationStack {
            if let final = PvPPreview.final(state) {
                PvPFinalView(screen: final) { _ in }
                    .navigationTitle(state.kind == .duel ? "Дуэль" : "Комната")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Победа") { PvPFinalPreview(state: PvPMatchFixtures.finishedVictory) }
#Preview("Поражение") { PvPFinalPreview(state: PvPMatchFixtures.finishedDefeat) }
#Preview("Победа техническая") { PvPFinalPreview(state: PvPMatchFixtures.finishedForfeitVictory) }
#Preview("Техпоражение") { PvPFinalPreview(state: PvPMatchFixtures.finishedForfeitDefeat) }
#Preview("Ничья") { PvPFinalPreview(state: PvPMatchFixtures.finishedDraw) }
#Preview("Оба пропали") { PvPFinalPreview(state: PvPMatchFixtures.finishedAbandoned) }
#Preview("Итог комнаты") { PvPFinalPreview(state: PvPMatchFixtures.finishedRoom) }
#Preview("Итог комнаты, первое место") { PvPFinalPreview(state: PvPMatchFixtures.finishedRoomWinner) }

#Preview("Строка фильма") {
    if let film = PvPPreview.final(PvPMatchFixtures.finishedRoom)?.films.last {
        PvPFinalFilmRow(film: film)
            .padding()
            .preferredColorScheme(.dark)
    }
}
#endif
