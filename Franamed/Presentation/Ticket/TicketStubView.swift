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
        VStack(alignment: .leading, spacing: TicketStyle.stubSpacing) {
            title
            filtersButton
            startButton
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: some View {
        Text(card.mode.displayName)
            .font(TicketStyle.title)
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    private var filtersButton: some View {
        Button(action: onOpenFilters) {
            VStack(alignment: .leading, spacing: TicketStyle.stubSpacing) {
                TicketMetaRow(
                    mediaType: card.mediaType,
                    source: card.mode.roundSource,
                    setup: setup
                )
                TicketFilterSummaryView(
                    summary: TicketFilterSummary(filters: setup.filters, genreNames: genreNames)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
    }

    private var startButton: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: onStart) {
                TicketBarcodeView(mediaType: card.mediaType, mode: card.mode)
                    .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TicketMetaRow: View {
    let mediaType: MediaType
    let source: RoundSource
    let setup: RoundSetup

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TicketStyle.metaSpacing) {
            Text(mediaType.displayName.uppercased())
                .lineLimit(1)
            if source == .tmdb && setup.filters.includeAdult {
                adultBadge
            }
            Spacer(minLength: 0)
            frameBadge
            switch source {
            case .tmdb: sortBadge
            case .curated: ShuffleIcon(mode: setup.shuffle)
            }
        }
        .font(TicketStyle.meta)
        .foregroundStyle(Color.black)
    }

    private var adultBadge: some View {
        Text("18+")
            .font(TicketStyle.fieldLabel.bold())
            .tracking(0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.white)
    }

    private var frameBadge: some View {
        HStack(spacing: TicketStyle.symbolTextSpacing) {
            Image(systemName: "film")
            Text("\(setup.frameCount)")
        }
        .lineLimit(1)
    }

    private var sortBadge: some View {
        HStack(spacing: TicketStyle.symbolTextSpacing) {
            Image(systemName: setup.filters.sortBy.ticketIcon)
            Text(setup.filters.sortBy.ticketLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .layoutPriority(0)
    }
}

#Preview {
    TicketStubView(
        card: TicketCard(mediaType: .movie, posterPath: nil, mode: .random),
        setup: RoundSetup(
            filters: MediaFilters(
                genres: [1, 2], yearRange: 1990...2026, minRating: 5,
                minVoteCount: 100, originalLanguages: ["en", "ru"], includeAdult: true
            ),
            frameCount: 6
        ),
        genreNames: ["Комедия", "Ужасы"],
        isInteractive: true,
        onOpenFilters: {},
        onStart: {}
    )
    .modifier(TicketStubFrame(width: 300, edgeStyle: .scalloped))
    .background(Color.white)
}

#Preview("Курируемый") {
    TicketStubView(
        card: TicketCard(mediaType: .movie, posterPath: nil, mode: .curated),
        setup: RoundSetup(filters: MediaFilters(genres: [1], minRating: 7), frameCount: 6, shuffle: .smart),
        genreNames: ["Комедия"],
        isInteractive: true,
        onOpenFilters: {},
        onStart: {}
    )
    .modifier(TicketStubFrame(width: 300, edgeStyle: .scalloped))
    .background(Color.white)
}
