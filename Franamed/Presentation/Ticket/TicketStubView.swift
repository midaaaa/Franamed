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
        VStack(alignment: .leading, spacing: TicketStyle.stubSpacing) {
            title
            filtersButton
            startButton
        }
        .buttonStyle(.plain)
        .padding(TicketStyle.stubPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(isInteractive)
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
                    includeAdult: setup.filters.includeAdult,
                    frameCount: setup.frameCount,
                    sortBy: setup.filters.sortBy
                )
                TicketFilterSummaryView(
                    summary: TicketFilterSummary(filters: setup.filters, genreNames: genreNames)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
    let includeAdult: Bool
    let frameCount: Int
    let sortBy: SortBy

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TicketStyle.metaSpacing) {
            Text(mediaType.displayName.uppercased())
                .lineLimit(1)
            if includeAdult {
                adultBadge
            }
            Spacer(minLength: 0)
            frameBadge
            sortBadge
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
            Text("\(frameCount)")
        }
        .lineLimit(1)
    }

    private var sortBadge: some View {
        HStack(spacing: TicketStyle.symbolTextSpacing) {
            Image(systemName: sortBy.ticketIcon)
            Text(sortBy.ticketLabel)
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
    .frame(width: 300)
    .background(Color.white)
}
