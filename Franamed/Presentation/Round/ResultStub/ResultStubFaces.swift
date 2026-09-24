//
//  ResultStubFaces.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import SwiftUI

struct ResultStubFront: View {
    let content: ResultStubContent

    var body: some View {
        ResultStubPaper(mirrored: true) {
            Text(content.title)
                .font(TicketStyle.title)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            if let authors = content.authors {
                Text("\(content.authorsLabel) \(authors)")
                    .font(TicketStyle.meta)
                    .foregroundStyle(.black.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if !content.meta.isEmpty {
                Text(content.meta)
                    .font(TicketStyle.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            HStack(alignment: .center) {
                Text(content.verdict)
                    .font(TicketStyle.fieldLabel)
                    .tracking(TicketStyle.fieldLabelTracking)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                ResultStubDots(used: content.attemptsUsed,
                               total: content.frameCount,
                               isCorrect: content.isCorrect)
            }

            Text(content.session.uppercased())
                .font(TicketStyle.serial)
                .tracking(TicketStyle.serialTracking)
                .foregroundStyle(.black.opacity(0.38))
        }
        .foregroundStyle(.black)
    }
}

struct ResultStubSetupBack: View {
    let mediaType: MediaType
    let filters: MediaFilters
    let frameCount: Int
    let genreNames: [String]

    var body: some View {
        ResultStubPaper {
            TicketStubBody(
                card: TicketCard(mediaType: mediaType, posterPath: nil, mode: .random),
                setup: RoundSetup(filters: filters, frameCount: frameCount),
                genreNames: genreNames
            )
            .allowsHitTesting(false)
        }
        .foregroundStyle(.black)
    }
}

#Preview("Лицо — победа") {
    ResultStubFront(content: ResultStubContent(
        item: MediaItem(id: 1, mediaType: .movie, title: "Оппенгеймер", originalTitle: "Oppenheimer",
                        releaseDate: "2023-07-19", overview: nil),
        mediaType: .movie, details: PreviewDetails.movie, outcome: .correct,
        attemptsUsed: 3, frameCount: 6))
    .padding()
    .background(.black)
}

#Preview("Лицо — поражение, длинное название") {
    ResultStubFront(content: ResultStubContent(
        item: MediaItem(id: 2, mediaType: .movie,
                        title: "Доктор Стрейнджлав",
                        originalTitle: "Dr. Strangelove or: How I Learned to Stop Worrying and Love the Bomb",
                        releaseDate: "1964-01-29", overview: nil),
        mediaType: .movie, details: PreviewDetails.movie, outcome: .incorrect,
        attemptsUsed: 6, frameCount: 6))
    .padding()
    .background(.black)
}

#Preview("Оборот — сетап") {
    ResultStubSetupBack(mediaType: .movie, filters: MediaFilters(), frameCount: 6,
                        genreNames: ["драма", "история"])
        .padding()
        .background(.black)
}
