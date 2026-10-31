//
//  PvPTablesView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPStandingsView: View {
    let rows: [PvPStandingRow]

    var body: some View {
        PvPCard(padding: 6) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    PvPStandingRowView(row: row)
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 86)
                    }
                }
            }
        }
        .animation(.snappy, value: rows)
    }
}

struct PvPStandingRowView: View {
    let row: PvPStandingRow

    var body: some View {
        HStack(spacing: 12) {
            Text(row.isTied ? "=\(row.place)" : "\(row.place)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(row.place == 1 ? PvPStyle.win : .secondary)
                .frame(width: 28, alignment: .trailing)
            PvPAvatarView(avatar: row.avatar, size: 32, isDimmed: row.isOut)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.body.weight(row.isYou ? .semibold : .regular))
                        .lineLimit(1)
                    if row.isYou {
                        Text("вы")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(row.score)
                .font(PvPStyle.score)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: PvPStyle.rowHeight)
    }
}

struct PvPResultsView: View {
    let rows: [PvPResultRow]

    var body: some View {
        PvPCard(padding: 6) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        PvPAvatarView(avatar: row.avatar, size: 32, isDimmed: !row.isSolved)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.isYou ? "Вы" : row.name)
                                .font(.body.weight(row.isYou ? .semibold : .regular))
                                .lineLimit(1)
                            Text(row.detail)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(row.isSolved ? Color.secondary : PvPStyle.miss)
                        }
                        Spacer(minLength: 0)
                        Text(row.points)
                            .font(PvPStyle.score)
                            .foregroundStyle(row.isSolved ? PvPStyle.hit : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: PvPStyle.rowHeight)
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 54)
                    }
                }
            }
        }
    }
}

struct PvPAnswerCardView: View {
    let answer: PvPAnswerCard
    var posterWidth: CGFloat = 110

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CachedRemoteImage(url: PvPImageLinks.poster(answer.posterPath))
                .frame(width: posterWidth, height: posterWidth * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if answer.posterPath == nil {
                        Image(systemName: "film")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(answer.title)
                    .font(PvPStyle.title)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = answer.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
#Preview("Таблица комнаты") {
    if let reveal = PvPPreview.reveal(PvPMatchFixtures.revealRoom) {
        PvPStandingsView(rows: reveal.standings)
            .padding()
            .preferredColorScheme(.dark)
    }
}

#Preview("Таблица, ничья") {
    if let final = PvPPreview.final(PvPMatchFixtures.finishedDraw) {
        PvPStandingsView(rows: final.standings)
            .padding()
            .preferredColorScheme(.dark)
    }
}

#Preview("Результаты фильма") {
    if let reveal = PvPPreview.reveal(PvPMatchFixtures.revealRoom) {
        PvPResultsView(rows: reveal.results)
            .padding()
            .preferredColorScheme(.dark)
    }
}

#Preview("Ответ без постера") {
    PvPAnswerCardView(answer: PvPAnswerCard(title: "Форрест Гамп", subtitle: "Forrest Gump · 1994", posterPath: nil))
        .padding()
        .preferredColorScheme(.dark)
}
#endif
