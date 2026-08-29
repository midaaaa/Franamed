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
            && lhs.showsMesh == rhs.showsMesh
            && lhs.tintsPaper == rhs.tintsPaper
            && lhs.resetToken == rhs.resetToken
            && lhs.returnToken == rhs.returnToken
            && lhs.returnStyle == rhs.returnStyle
            && lhs.posterZoom == rhs.posterZoom
            && lhs.filtersZoom == rhs.filtersZoom
            && lhs.probe === rhs.probe
    }

    let card: TicketCard
    let setup: RoundSetup
    let genreNames: [String]
    let width: CGFloat
    let posterHeight: CGFloat
    let isStubGrabEnabled: Bool
    let isRasterized: Bool
    var hidesStub: Bool = false
    var showsMesh: Bool = true
    var tintsPaper: Bool = false
    let resetToken: Int
    let returnToken: Int
    var returnStyle: TearReturnStyle = .flat
    let posterZoom: Namespace.ID
    let filtersZoom: Namespace.ID
    let onOpenFilters: () -> Void
    let onStart: () -> Void
    var onReturnChange: ((Bool) -> Void)?
    var onStubAwayChange: ((Bool) -> Void)?
    var probe: TearFrameRateProbe?

    @Environment(\.displayScale) private var displayScale

    private var pixelGrid: PixelGrid { PixelGrid(displayScale: displayScale) }
    @State private var measuredStubHeight: CGFloat = 0
    @State private var posterImage: UIImage?

    private var stubHeight: CGFloat {
        guard measuredStubHeight > 0 else { return 0 }
        return pixelGrid.evenAligned(measuredStubHeight, rule: .up)
    }

    private var tearConfig: TicketTearConfig {
        var config = TicketTearConfig()
        config.stubSide = .bottom
        config.stubExtent = stubHeight > 0 ? stubHeight : 140
        config.pitch = max(width - 2 * TicketStyle.tearNotchRadius, 1) / 9
        config.holeFraction = 18.0 / 27.0
        config.holeHalfWidth = 2.0
        config.perfEndInset = TicketStyle.tearNotchRadius
        config.showsMesh = showsMesh
        config.returnStyle = returnStyle
        return config
    }

    private var tearResetToken: Int {
        resetToken &* TicketGameMode.allCases.count &+ card.mode.rawValue
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
        TicketTear(config: tearConfig, resetToken: tearResetToken,
                   contentID: contentID, isGrabEnabled: isStubGrabEnabled,
                   rasterizesContent: isRasterized, returnToken: returnToken,
                   onComplete: onStart, onReturnChange: onReturnChange,
                   onStubAwayChange: onStubAwayChange, probe: probe) {
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
            .frame(width: width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredStubHeight = $0 }
            .frame(height: stubHeight > 0 ? stubHeight : nil, alignment: .top)
            .background(paper)
            .modifier(StubVisibility(isHidden: hidesStub))
            .matchedTransitionSource(id: card.mediaType, in: filtersZoom)
        }
        .frame(width: width)
        .mask(TicketPerforationShape(tearLineOffset: posterHeight,
                                     tearLineSlots: TearPerforation(config: tearConfig, length: width)))
    }

    private var paper: Color { tintsPaper ? .red : .white }

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
        resetToken: 0,
        returnToken: 0,
        posterZoom: posterZoom,
        filtersZoom: filtersZoom,
        onOpenFilters: {},
        onStart: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
