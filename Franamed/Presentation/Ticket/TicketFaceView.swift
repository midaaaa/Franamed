//
//  TicketFaceView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.08.2026.
//

import SwiftUI

struct TicketFaceView: View, Equatable {

    static func == (lhs: TicketFaceView, rhs: TicketFaceView) -> Bool {
        lhs.contentID == rhs.contentID
            && lhs.width == rhs.width
            && lhs.posterHeight == rhs.posterHeight
            && lhs.isStubGrabEnabled == rhs.isStubGrabEnabled
            && lhs.isRasterized == rhs.isRasterized
            && lhs.hidesStub == rhs.hidesStub
            && lhs.edgeStyle == rhs.edgeStyle
            && lhs.returnToken == rhs.returnToken
            && lhs.posterZoom == rhs.posterZoom
            && lhs.filtersZoom == rhs.filtersZoom
    }

    let card: TicketCard
    let setup: RoundSetup
    let genreNames: [String]
    let width: CGFloat
    let posterHeight: CGFloat
    let isStubGrabEnabled: Bool
    let isRasterized: Bool
    var hidesStub: Bool = false
    var edgeStyle: TicketEdgeStyle = .straight
    let returnToken: Int
    let posterZoom: Namespace.ID
    let filtersZoom: Namespace.ID
    let onOpenFilters: () -> Void
    let onStart: () -> Void
    var onReturnChange: ((Bool) -> Void)?
    var onStubAwayChange: ((Bool) -> Void)?

    @State private var posterImage: UIImage?

    private var tearConfig: TicketTearConfig {
        var config = TicketTearConfig.ticket(width: width)
        config.stubExtent = TicketStubMetrics.height(width: width, edgeStyle: edgeStyle)
        return config
    }

    private struct ContentID: Hashable {
        let mediaType: MediaType
        let mode: TicketGameMode
        let posterPath: String?
        let setup: RoundSetup
        let genreNames: [String]
    }

    private var contentID: ContentID {
        ContentID(mediaType: card.mediaType, mode: card.mode, posterPath: card.posterPath,
                  setup: setup, genreNames: genreNames)
    }

    var body: some View {
        TicketTear(config: tearConfig, stubShape: ResultStubShape(edgeStyle: edgeStyle),
                   resetToken: card.mode.rawValue,
                   contentID: contentID, isGrabEnabled: isStubGrabEnabled,
                   isContentComplete: !hidesStub,
                   rasterizesContent: isRasterized, returnToken: returnToken,
                   onComplete: onStart, onReturnChange: onReturnChange,
                   onStubAwayChange: onStubAwayChange) {
            ticket
        }
        .task(id: posterURL) { await loadPoster() }
    }

    private var ticket: some View {
        VStack(spacing: 0) {
            poster
                .frame(width: width, height: posterHeight)
                .clipped()
                .matchedTransitionSource(id: card.mediaType, in: posterZoom)

            TicketStubView(
                card: card,
                setup: setup,
                genreNames: genreNames,
                isInteractive: isStubGrabEnabled,
                onOpenFilters: onOpenFilters,
                onStart: onStart
            )
            .modifier(TicketStubFrame(width: width, edgeStyle: edgeStyle))
            .background(paper)
            .modifier(StubVisibility(isHidden: hidesStub))
            .matchedTransitionSource(id: card.mediaType, in: filtersZoom)
        }
        .frame(width: width)
        .mask(TicketPerforationShape(tearLineOffset: posterHeight,
                                     tearLineSlots: TearPerforation(config: tearConfig, length: width),
                                     edgeStyle: edgeStyle))
    }

    private var paper: Color { TicketStyle.paper }

    @ViewBuilder
    private var poster: some View {
        if let posterImage {
            Image(uiImage: posterImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholder
        }
    }

    private func loadPoster() async {
        guard let url = posterURL else {
            posterImage = nil
            return
        }
        if let cached = ImageCache.shared.image(for: url) {
            posterImage = cached
            return
        }
        posterImage = nil
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        ImageCache.shared.store(image, for: url)
        posterImage = image
    }

    private var posterURL: URL? {
        card.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w780/\($0)") }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.9), Color(white: 0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "film")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

}

#Preview {
    @Previewable @Namespace var posterZoom
    @Previewable @Namespace var filtersZoom

    TicketFaceView(
        card: TicketCard(mediaType: .movie, posterPath: nil, mode: .random),
        setup: RoundSetup(filters: MediaFilters(genres: [1], minRating: 5), frameCount: 6),
        genreNames: ["Комедия"],
        width: 300,
        posterHeight: 450,
        isStubGrabEnabled: true,
        isRasterized: false,
        returnToken: 0,
        posterZoom: posterZoom,
        filtersZoom: filtersZoom,
        onOpenFilters: {},
        onStart: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
