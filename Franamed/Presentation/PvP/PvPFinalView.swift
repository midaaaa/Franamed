//
//  PvPFinalView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

/// The match summary in the hall: the result is on the cinema screen, the actions sit where the
/// answer form was, and the full table and every film open in a native sheet.
struct PvPFinalBar: View {
    let screen: PvPFinalScreen
    let onAction: (PvPAction.Kind) -> Void

    @State private var isShowingDetails = false

    var body: some View {
        VStack(spacing: 10) {
            if let hint = screen.hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        isShowingDetails = true
                    } label: {
                        Label("Итоги", systemImage: "list.number")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Все итоги")
                    ShareLink(item: screen.shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Поделиться итогом")
                    if let primary = screen.primary {
                        PvPPrimaryButton(title: primary.title, isEnabled: primary.isEnabled) {
                            Haptics.shared.play(.menuSelect)
                            onAction(primary.kind)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: PvPStyle.maxWidth)
        .padding(.horizontal, AnswerBarLayout.restingInset)
        .sheet(isPresented: $isShowingDetails) {
            PvPFinalDetails(screen: screen)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Everything behind the summary: the table and each film with your result.
struct PvPFinalDetails: View {
    let screen: PvPFinalScreen

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PvPPage {
                if let duel = screen.duel {
                    PvPCard { PvPDuelBarsView(bars: duel) }
                }
                PvPKicker(text: "Итоги")
                PvPStandingsView(rows: screen.standings)
                PvPKicker(text: screen.solvedLine)
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
            .navigationTitle(screen.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", systemImage: "checkmark") { dismiss() }
                }
            }
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
        if let final = PvPPreview.final(state) {
            PvPFinalBar(screen: final) { _ in }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 24)
                .background(.black)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview("Панель: победа") { PvPFinalPreview(state: PvPMatchFixtures.finishedVictory) }
#Preview("Панель: поражение") { PvPFinalPreview(state: PvPMatchFixtures.finishedDefeat) }
#Preview("Панель: техпоражение") { PvPFinalPreview(state: PvPMatchFixtures.finishedForfeitDefeat) }
#Preview("Панель: комната, гость") { PvPFinalPreview(state: PvPMatchFixtures.finishedRoom) }
#Preview("Панель: комната, хост") { PvPFinalPreview(state: PvPMatchFixtures.finishedRoomWinner) }

#Preview("Все итоги: дуэль") {
    if let final = PvPPreview.final(PvPMatchFixtures.finishedVictory) {
        PvPFinalDetails(screen: final).preferredColorScheme(.dark)
    }
}

#Preview("Все итоги: комната") {
    if let final = PvPPreview.final(PvPMatchFixtures.finishedRoom) {
        PvPFinalDetails(screen: final).preferredColorScheme(.dark)
    }
}

#Preview("Строка фильма") {
    if let film = PvPPreview.final(PvPMatchFixtures.finishedRoom)?.films.last {
        PvPFinalFilmRow(film: film)
            .padding()
            .preferredColorScheme(.dark)
    }
}
#endif
