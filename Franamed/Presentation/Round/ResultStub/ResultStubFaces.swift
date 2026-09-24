//
//  ResultStubFaces.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import SwiftUI

enum ResultStubMetrics {
    static let height: CGFloat = 210
    static let tornInset: CGFloat = 6

    @MainActor
    static var scallopInset: CGFloat {
        TicketPerforationShape.scallopDepth(width: width)
    }

    @MainActor
    static var width: CGFloat {
        max(200, WindowMetrics.size.width - TicketStyle.screenInset * 2)
    }
}

struct ResultStubPaper<Content: View>: View {
    var mirrored = false
    @ViewBuilder let content: Content

    @AppStorage(DebugSettings.straightEdgeKey) private var usesStraightEdges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.top, TicketStyle.stubPadding + ResultStubMetrics.tornInset)
        .padding(.bottom, TicketStyle.stubPadding
                 + (usesStraightEdges ? 0 : ResultStubMetrics.scallopInset))
        .padding(.horizontal, TicketStyle.stubPadding)
        .frame(width: ResultStubMetrics.width,
               height: ResultStubMetrics.height,
               alignment: .topLeading)
        .background(TicketStyle.paper)
        .clipShape(ResultStubShape(edgeStyle: TicketEdgeStyle(usesStraightEdges: usesStraightEdges),
                                   mirrored: mirrored))
        .environment(\.colorScheme, .light)
    }
}

struct ResultStubDots: View {
    let used: Int
    let total: Int
    let isCorrect: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(color(at: index))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func color(at index: Int) -> Color {
        guard index < used else { return .black.opacity(0.18) }
        if index == used - 1 { return isCorrect ? .green : .red }
        return .black.opacity(0.45)
    }
}

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
