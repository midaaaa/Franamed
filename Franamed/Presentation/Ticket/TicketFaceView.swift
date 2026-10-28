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
            && lhs.tearEdge == rhs.tearEdge
            && lhs.tearOverscan == rhs.tearOverscan
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
    var tearEdge = TearEdge.plain
    var tearOverscan: CGFloat = 0
    let returnToken: Int
    let posterZoom: Namespace.ID
    let filtersZoom: Namespace.ID
    let onOpenFilters: () -> Void
    let onStart: () -> Void
    let onOpenPoster: () -> Void
    var onReturnChange: ((Bool) -> Void)?
    var onStubAwayChange: ((Bool) -> Void)?
    var onResumableChange: ((Bool) -> Void)?

    @State private var posterImage: UIImage?
    @Environment(\.displayScale) private var displayScale

    private static let posterWidthStep: CGFloat = 256

    private var tearConfig: TicketTearConfig {
        var config = TicketTearConfig.ticket(width: width)
        config.stubExtent = TicketStubMetrics.height(width: width, edgeStyle: edgeStyle)
        config.canvasPadding = max(config.canvasPadding, tearOverscan)
        config.edge = tearEdge
        return config
    }

    private struct ContentID: Hashable {
        let mediaType: MediaType
        let mode: TicketGameMode
        let posterPath: String?
        let setup: RoundSetup
        let genreNames: [String]
        let playlist: PlaylistTicket?
    }

    private var contentID: ContentID {
        ContentID(mediaType: card.mediaType, mode: card.mode, posterPath: card.posterPath,
                  setup: setup, genreNames: genreNames, playlist: card.playlist)
    }

    var body: some View {
        TicketTear(config: tearConfig, stubShape: ResultStubShape(edgeStyle: edgeStyle, edge: tearEdge),
                   resetToken: card.mode.rawValue,
                   contentID: contentID, isGrabEnabled: isStubGrabEnabled && card.canTear,
                   isContentComplete: !hidesStub,
                   rasterizesContent: isRasterized, returnToken: returnToken,
                   onComplete: onStart, onReturnChange: onReturnChange,
                   onStubAwayChange: onStubAwayChange,
                   onResumableChange: onResumableChange) {
            ticket
        }
        .task(id: posterSource) { await loadPoster() }
    }

    private var ticket: some View {
        VStack(spacing: 0) {
            poster
                .frame(width: width, height: posterHeight)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenPoster)
                .matchedTransitionSource(id: card.mediaType, in: posterZoom)

            TicketStubView(
                card: card,
                setup: setup,
                genreNames: genreNames,
                width: width,
                edgeStyle: edgeStyle,
                isInteractive: isStubGrabEnabled,
                onOpenFilters: onOpenFilters,
                onStart: onStart
            )
            .background(paper)
            .modifier(StubVisibility(isHidden: hidesStub))
            .matchedTransitionSource(id: card.mediaType, in: filtersZoom)
        }
        .frame(width: width)
        .mask(TicketPerforationShape(tearLineOffset: posterHeight,
                                     tearLineSlots: TearPerforation(config: tearConfig, length: width),
                                     edgeStyle: edgeStyle,
                                     designSize: CGSize(width: width, height: posterHeight + tearConfig.stubExtent)))
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
        guard let source = posterSource else {
            posterImage = nil
            return
        }
        let cached = ImageCache.shared.image(for: source.url)
        if let cached, cached.size.width * cached.scale >= source.pixelWidth {
            posterImage = cached
            return
        }
        posterImage = cached
            ?? posterURL.flatMap(ImageCache.shared.image(for:))
            ?? posterURL.flatMap(TMDBImageSize.small(of:)).flatMap(ImageCache.shared.image(for:))
        let fitting = source.pixelWidth > 0 ? source.pixelWidth : nil
        guard let image = await FrameDownloads.shared.image(for: source.url, fittingPixelWidth: fitting) else { return }
        ImageCache.shared.store(image, for: source.url)
        posterImage = image
    }

    private struct PosterSource: Hashable {
        let url: URL
        let pixelWidth: CGFloat
    }

    private var posterSource: PosterSource? {
        guard let url = posterURL else { return nil }
        let pixelWidth = width * displayScale
        guard pixelWidth > TMDBImageSize.largePixelWidth, let original = TMDBImageSize.original(of: url) else {
            return PosterSource(url: url, pixelWidth: 0)
        }
        let stepped = (pixelWidth / Self.posterWidthStep).rounded(.up) * Self.posterWidthStep
        return PosterSource(url: original, pixelWidth: stepped)
    }

    private var posterURL: URL? {
        if card.mode == .collection { return card.playlist?.coverURL }
        return card.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w780/\($0)") }
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
        onStart: {},
        onOpenPoster: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
