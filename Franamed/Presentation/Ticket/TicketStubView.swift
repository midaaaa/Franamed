//
//  TicketStubView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.08.2026.
//

import SwiftUI

struct TicketStubView: View {
    let card: TicketCard
    let setup: RoundSetup
    let genreNames: [String]
    let isInteractive: Bool
    let onOpenFilters: () -> Void
    let onStart: () -> Void

    var body: some View {
        TicketStubBody(card: card, setup: setup, genreNames: genreNames,
                       onOpenFilters: onOpenFilters, onStart: onStart)
            .allowsHitTesting(isInteractive)
    }
}

struct TicketStubBody: View {
    let card: TicketCard
    let setup: RoundSetup
    let genreNames: [String]
    var onOpenFilters: () -> Void = {}
    var onStart: () -> Void = {}

    var body: some View {
        if card.mode == .collection {
            PlaylistStubBody(mediaType: card.mediaType, mode: card.mode, playlist: card.playlist,
                             onOpenPicker: onOpenFilters, onStart: onStart)
        } else {
            regularBody
        }
    }

    private var regularBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            TicketStubHeader(title: card.mode.displayName, media: card.mediaType.displayName) {
                if card.mode.roundSource == .curated {
                    ShuffleIcon(mode: setup.shuffle)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            Button(action: onOpenFilters) {
                TicketFilterSummaryView(summary: TicketFilterSummary(setup: setup, genreNames: genreNames))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            Button(action: onStart) {
                TicketPlayCode(caption: "ИГРАТЬ", serial: serial)
                    .contentShape(Rectangle())
            }
            .padding(.top, TicketStyle.codeGap)
        }
        .buttonStyle(.plain)
        .modifier(TicketStubLayout(serial: serial))
    }

    private var serial: String {
        card.mode.serial(mediaType: card.mediaType, frameCount: setup.frameCount)
    }
}

#Preview("Наугад — всё задано") {
    TicketStubView(
        card: TicketCard(mediaType: .movie, posterPath: nil, mode: .random),
        setup: RoundSetup(
            filters: MediaFilters(
                genres: [1, 2, 3, 4], yearRange: 1990...2010, minRating: 7.5,
                minVoteCount: 500, originalLanguages: ["en", "ru", "fr"]
            ),
            frameCount: 3
        ),
        genreNames: ["Комедия", "Ужасы", "Триллер", "Драма"],
        isInteractive: true,
        onOpenFilters: {},
        onStart: {}
    )
    .modifier(TicketStubFrame(width: 293, edgeStyle: .straight))
    .background(TicketStyle.paper)
}

#Preview("Сеанс — по умолчанию") {
    TicketStubView(
        card: TicketCard(mediaType: .movie, posterPath: nil, mode: .curated),
        setup: RoundSetup(),
        genreNames: [],
        isInteractive: true,
        onOpenFilters: {},
        onStart: {}
    )
    .modifier(TicketStubFrame(width: 293, edgeStyle: .scalloped))
    .background(TicketStyle.paper)
}
