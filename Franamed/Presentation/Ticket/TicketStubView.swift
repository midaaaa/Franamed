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
    let width: CGFloat
    let edgeStyle: TicketEdgeStyle
    let isInteractive: Bool
    let onOpenFilters: () -> Void
    let onStart: () -> Void

    var body: some View {
        TicketStubBody(card: card, setup: setup, genreNames: genreNames)
            .modifier(TicketStubFrame(width: width, edgeStyle: edgeStyle))
            .overlay(alignment: .top) { tapZones.allowsHitTesting(isInteractive) }
    }

    private var hasPlayCode: Bool {
        card.mode != .collection || card.playlist != nil
    }

    private var tapZones: some View {
        VStack(spacing: 0) {
            Button(action: onOpenFilters) { tapZone }
                .frame(height: hasPlayCode ? TicketStubMetrics.codeZoneTop * TicketStyle.zoom(forWidth: width) : nil)
            if hasPlayCode {
                Button(action: onStart) { tapZone }
            }
        }
        .buttonStyle(TicketStubTapStyle())
    }

    private var tapZone: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}

private struct TicketStubTapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct TicketStubBody: View {
    let card: TicketCard
    let setup: RoundSetup
    let genreNames: [String]

    var body: some View {
        if card.mode == .collection {
            PlaylistStubBody(mediaType: card.mediaType, mode: card.mode, playlist: card.playlist)
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
            TicketFilterSummaryView(summary: TicketFilterSummary(setup: setup, genreNames: genreNames))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            TicketPlayCode(caption: "ИГРАТЬ", serial: serial)
                .padding(.top, TicketStyle.codeGap)
        }
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
        width: 293,
        edgeStyle: .straight,
        isInteractive: true,
        onOpenFilters: {},
        onStart: {}
    )
    .background(TicketStyle.paper)
}

#Preview("Сеанс — по умолчанию") {
    TicketStubView(
        card: TicketCard(mediaType: .movie, posterPath: nil, mode: .curated),
        setup: RoundSetup(),
        genreNames: [],
        width: 293,
        edgeStyle: .scalloped,
        isInteractive: true,
        onOpenFilters: {},
        onStart: {}
    )
    .background(TicketStyle.paper)
}
