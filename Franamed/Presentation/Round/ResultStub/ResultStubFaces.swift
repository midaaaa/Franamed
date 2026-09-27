//
//  ResultStubFaces.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import SwiftUI

struct ResultStubFront: View {
    let content: ResultStubContent
    var hidesDetails = false

    private static let creditsLines = 2

    private static func firstFitting(_ variants: [String], font: UIFont, lines: Int) -> String? {
        let width = ResultStubMetrics.width - TicketStyle.stubPadding * 2
        let limit = font.lineHeight * CGFloat(lines) + 1
        return variants.first { variant in
            let box = (variant as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
            return box.height <= limit
        } ?? variants.last
    }

    var body: some View {
        ResultStubPaper(mirrored: true) {
            serviceLine
            details
        }
        .foregroundStyle(.black)
    }

    private var serviceLine: some View {
        HStack(alignment: .center) {
            ResultStubDots(marks: content.marks, current: content.currentFrame)
            Spacer(minLength: 8)
            Text(content.session)
                .font(TicketStyle.serial)
                .foregroundStyle(.black.opacity(0.38))
                .lineLimit(1)
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var details: some View {
        Group {
            texts
        }
        .opacity(hidesDetails ? 0 : 1)
    }

    @ViewBuilder
    private var texts: some View {
        Text(content.title)
            .font(TicketStyle.title)
            .lineLimit(3)
            .minimumScaleFactor(0.7)

        if let credits = Self.firstFitting(content.credits, font: TicketStyle.metaUIFont, lines: Self.creditsLines) {
            Text(credits)
                .font(TicketStyle.meta)
                .foregroundStyle(.black.opacity(0.7))
                .lineLimit(Self.creditsLines)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }

        if !content.meta.isEmpty {
            Text(content.meta)
                .font(TicketStyle.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }

        Spacer(minLength: 0)

        Text(content.verdict)
            .font(TicketStyle.fieldLabel)
            .tracking(TicketStyle.fieldLabelTracking)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
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

private struct ResultStubGallery: View {
    private struct Case: Identifiable {
        let id: String
        let item: MediaItem
        let details: MediaDetails
        let outcome: RoundOutcome?
        let attempts: Int
        let current: Int
    }

    private static let oppenheimer = MediaItem(id: 1, mediaType: .movie, title: "Оппенгеймер",
                                               originalTitle: "Oppenheimer", releaseDate: "2023-07-19", overview: nil)
    private static let borat = MediaItem(id: 2, mediaType: .movie, title: "Борат",
                                         originalTitle: "Borat: Cultural Learnings of America for Make Benefit Glorious Nation of Kazakhstan",
                                         releaseDate: "2006-11-02", overview: nil)
    private static let everything = MediaItem(id: 5, mediaType: .movie, title: "Всё везде и сразу",
                                              originalTitle: "Everything Everywhere All at Once",
                                              releaseDate: "2022-03-11", overview: nil)
    private static let lost = MediaItem(id: 3, mediaType: .tv, title: "Остаться в живых",
                                        originalTitle: "Lost", releaseDate: "2004-09-22", overview: nil)
    private static let stargate = MediaItem(id: 4, mediaType: .tv, title: "Звёздные врата: ЗВ-1",
                                            originalTitle: "Stargate SG-1", releaseDate: "1997-07-27", overview: nil)
    private static let simpsons = MediaItem(id: 6, mediaType: .tv, title: "Симпсоны",
                                            originalTitle: "The Simpsons", releaseDate: "1989-12-17", overview: nil)

    private let cases = [
        Case(id: "до ответа — видна только строка", item: oppenheimer, details: PreviewDetails.movie,
             outcome: nil, attempts: 2, current: 1),
        Case(id: "2 режиссёра · с 3-й · смотрю 5-й",
             item: everything, details: MediaDetails(runtimeMinutes: 139, firstYear: 2022, certification: "18+",
                                                     authors: ["Дэниел Кван", "Дэниел Шайнерт"]),
             outcome: .correct, attempts: 3, current: 4),
        Case(id: "длинное название · мимо",
             item: borat, details: MediaDetails(runtimeMinutes: 84, firstYear: 2006, certification: "18+",
                                                authors: ["Ларри Чарльз"]),
             outcome: .incorrect, attempts: 6, current: 2),
        Case(id: "сериал · 3 создателя в 2 строки · с 1-й",
             item: lost, details: MediaDetails(firstYear: 2004, lastYear: 2010, seasonCount: 6, certification: "16+",
                                               authors: ["Джей Джей Абрамс", "Деймон Линделоф", "Джеффри Либер"]),
             outcome: .correct, attempts: 1, current: 0),
        Case(id: "5 авторов → и ещё N",
             item: lost, details: MediaDetails(firstYear: 2004, lastYear: 2010, seasonCount: 6, certification: "16+",
                                               authors: ["Джей Джей Абрамс", "Деймон Линделоф", "Джеффри Либер",
                                                         "Карлтон Кьюз", "Дэвид Фьюри"]),
             outcome: .incorrect, attempts: 6, current: 1),
        Case(id: "отменён · 10 сезонов — шрифт меньше",
             item: stargate, details: MediaDetails(firstYear: 1997, lastYear: 2007, seasonCount: 10, isCanceled: true,
                                                   certification: "12+", authors: ["Брэд Райт", "Джонатан Гласснер"]),
             outcome: .correct, attempts: 6, current: 5),
        Case(id: "сериал идёт · 36 сезонов · мимо",
             item: simpsons, details: MediaDetails(firstYear: 1989, seasonCount: 36, isInProduction: true,
                                                   certification: "12+", authors: ["Мэтт Грейнинг"]),
             outcome: .incorrect, attempts: 6, current: 0)
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(cases) { c in
                    card(c.id) {
                        ResultStubFront(content: ResultStubContent(
                            item: c.item, mediaType: c.item.mediaType, details: c.details,
                            outcome: c.outcome, attemptsUsed: max(c.attempts, 1),
                            marks: ResultStubMark.live(frameCount: 6, attemptsMade: c.attempts,
                                                       revealedCount: c.outcome == .correct ? 6 : c.attempts + 1,
                                                       outcome: c.outcome),
                            currentFrame: c.current),
                            hidesDetails: c.outcome == nil)
                    }
                }
                card("оборот — сетап") {
                    ResultStubSetupBack(mediaType: .movie, filters: MediaFilters(), frameCount: 6,
                                        genreNames: ["драма", "история"])
                }
            }
            .padding()
        }
        .background(.black)
    }

    private func card(_ label: String, @ViewBuilder face: () -> some View) -> some View {
        VStack(spacing: 6) {
            face()
            Text(label).font(.caption).foregroundStyle(.gray)
        }
    }
}

#Preview("Корешок — все сценарии") {
    ResultStubGallery()
}
