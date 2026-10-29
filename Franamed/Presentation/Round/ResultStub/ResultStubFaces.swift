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
    var clipsShape = true

    static let stripHeight: CGFloat = 18
    static let titleGap: CGFloat = 7
    static let factsSpacing: CGFloat = 12
    private static let shareLink = "franamed.app/s/xk3p"

    var body: some View {
        let ink = TicketInk.stub(for: content.mediaType)
        ResultStubPaper(mirrored: true, clipsShape: clipsShape, edge: content.tearEdge, ink: ink) {
            VStack(alignment: .leading, spacing: 0) {
                serviceLine
                details.opacity(hidesDetails ? 0 : 1)
            }
            .modifier(TicketStubLayout())
            .environment(\.ticketInk, ink)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Self.titleGap)
            ResultStubTitle(text: content.title)
            Spacer(minLength: Self.titleGap)
            HStack(alignment: .bottom, spacing: Self.factsSpacing) {
                ResultStubFacts(content: content)
                TicketCodeImage(image: TicketCode.qr(Self.shareLink))
                    .frame(width: ResultStubFacts.height, height: ResultStubFacts.height)
            }
        }
    }

    private var serviceLine: some View {
        HStack(spacing: 8) {
            Text(content.session)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            ResultStubDots(progress: content.progress)
        }
        .frame(height: Self.stripHeight)
    }
}

private struct ResultStubTitle: View {
    let text: String

    private static let width = TicketStyle.stubBodyWidth
    private static let slack: CGFloat = 6
    private static let budget = TicketStyle.stubBodyHeight - ResultStubFront.stripHeight
        - ResultStubFront.titleGap * 2 - ResultStubFacts.height - slack
    private static let sizes = stride(from: CGFloat(26), through: 12, by: -0.5)

    var body: some View {
        let fit = Self.fit(text)
        Text(text)
            .font(.system(size: fit.size, weight: .heavy))
            .lineLimit(fit.lines)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func fit(_ text: String) -> (size: CGFloat, lines: Int) {
        for size in sizes {
            let font = UIFont.systemFont(ofSize: size, weight: .heavy)
            let box = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
            if box.height <= budget + 1 { return (size, Int((box.height / font.lineHeight).rounded())) }
        }
        return (12, 4)
    }
}

private struct ResultStubFacts: View {
    let content: ResultStubContent

    private static let font = TicketStyle.valueUIFont
    private static let opticalGap: CGFloat = 11
    private static let tagHeight: CGFloat = 15
    private static let tagStroke: CGFloat = 1.2
    static let height = (font.capHeight * 2 + opticalGap * 2 + tagHeight).rounded()
    private static let width = TicketStyle.stubBodyWidth - height - ResultStubFront.factsSpacing

    var body: some View {
        let font = Self.font
        let capInset = font.leading / 2 + font.ascender - font.capHeight
        let step = font.capHeight + Self.opticalGap
        ZStack(alignment: .topLeading) {
            row(credits).offset(y: -capInset)
            row(content.meta).offset(y: step - capInset)
            if let certification = content.certification {
                tag(certification).offset(y: step * 2)
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
    }

    private var credits: String? {
        content.credits.first { ($0 as NSString).size(withAttributes: [.font: Self.font]).width <= Self.width }
            ?? content.credits.last
    }

    private func row(_ text: String?) -> some View {
        Text(text ?? "")
            .font(TicketStyle.value(isSet: false))
            .lineLimit(1)
            .minimumScaleFactor(TicketStyle.minimumScale)
            .frame(width: Self.width, height: Self.font.lineHeight, alignment: .leading)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .padding(.horizontal, 3.5)
            .frame(height: Self.tagHeight - Self.tagStroke)
            .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(lineWidth: Self.tagStroke))
            .padding(Self.tagStroke / 2)
    }
}

struct ResultStubSetupBack: View {
    let card: TicketCard
    let setup: RoundSetup
    let genreNames: [String]
    var edge = TearEdge.plain

    var body: some View {
        let ink = TicketInk.stub(for: card.mediaType)
        ResultStubPaper(edge: edge, ink: ink) {
            TicketStubBody(card: card, setup: setup, genreNames: genreNames)
                .environment(\.ticketStubIsUsed, true)
                .environment(\.ticketInk, ink)
                .allowsHitTesting(false)
        }
    }
}

private struct ResultStubGallery: View {
    private struct Case: Identifiable {
        let id: String
        let item: MediaItem
        let details: MediaDetails
        let outcome: RoundOutcome?
        let attempts: Int
        let current: Int?
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

    private static let chernobyl = MediaItem(id: 7, mediaType: .tv, title: "Чернобыль",
                                             originalTitle: "Chernobyl", releaseDate: "2019-05-06", overview: nil)
    private static let stalker = MediaItem(id: 8, mediaType: .movie, title: "Сталкер",
                                           originalTitle: "Stalker", releaseDate: "1979-05-25", overview: nil)
    private static let planetEarth = MediaItem(id: 9, mediaType: .tv, title: "Планета Земля",
                                               originalTitle: "Planet Earth", releaseDate: "2006-03-05", overview: nil)

    private let cases = [
        Case(id: "до ответа — видна только полоска", item: oppenheimer, details: PreviewDetails.movie,
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
        Case(id: "5 авторов → +N",
             item: lost, details: MediaDetails(firstYear: 2004, lastYear: 2010, seasonCount: 6, certification: "16+",
                                               authors: ["Джей Джей Абрамс", "Деймон Линделоф", "Джеффри Либер",
                                                         "Карлтон Кьюз", "Дэвид Фьюри"]),
             outcome: .incorrect, attempts: 6, current: 1),
        Case(id: "отменён · 10 сезонов",
             item: stargate, details: MediaDetails(firstYear: 1997, lastYear: 2007, seasonCount: 10,
                                                   certification: "12+", authors: ["Брэд Райт", "Джонатан Гласснер"]),
             outcome: .correct, attempts: 6, current: 5),
        Case(id: "сериал идёт · 36 сезонов · мимо",
             item: simpsons, details: MediaDetails(firstYear: 1989, seasonCount: 36, isInProduction: true,
                                                   certification: "12+", authors: ["Мэтт Грейнинг"]),
             outcome: .incorrect, attempts: 6, current: 0),
        Case(id: "мини-сериал",
             item: chernobyl, details: MediaDetails(firstYear: 2019, lastYear: 2019, seasonCount: 1, isMiniseries: true,
                                                    certification: "18+", authors: ["Крейг Мейзин"]),
             outcome: .correct, attempts: 2, current: nil),
        Case(id: "пусто · нет возраста и длительности",
             item: stalker, details: MediaDetails(firstYear: 1979, authors: ["Андрей Тарковский"]),
             outcome: .correct, attempts: 1, current: nil),
        Case(id: "пусто · сериал без авторов",
             item: planetEarth, details: MediaDetails(firstYear: 2006, lastYear: 2006, seasonCount: 1, isMiniseries: true),
             outcome: .incorrect, attempts: 6, current: nil)
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(cases) { c in
                    card(c.id) {
                        ResultStubFront(content: content(c), hidesDetails: c.outcome == nil)
                    }
                }
                ForEach([cases[1], cases[6]]) { c in
                    card("поделиться без ответа · \(c.id)") {
                        ResultStubFront(content: content(c).concealed())
                    }
                }
                card("оборот — сетап") {
                    ResultStubSetupBack(card: TicketCard(mediaType: .movie, posterPath: nil, mode: .random),
                                        setup: RoundSetup(filters: MediaFilters(), frameCount: 6),
                                        genreNames: ["драма", "история"])
                }
            }
            .padding()
        }
        .background(.black)
    }

    private func content(_ c: Case) -> ResultStubContent {
        ResultStubContent(item: c.item, mediaType: c.item.mediaType, details: c.details,
                          progress: ResultStubProgress(frameCount: 6, attemptsMade: c.attempts,
                                                       revealedCount: c.outcome == .correct ? 6 : c.attempts + 1,
                                                       outcome: c.outcome, currentFrame: c.current))
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
