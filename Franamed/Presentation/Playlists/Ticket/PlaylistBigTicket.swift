//
//  PlaylistBigTicket.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import SwiftUI

struct PlaylistBigTicket: View {
    let entry: PlaylistEntry
    let display: PlaylistEntryDisplay
    let number: Int
    let playlist: PlaylistTicket?
    let details: MediaDetails?
    let width: CGFloat
    var isLive = true
    var snapshotter: FlipSnapshotter?
    var isStubLifted = false

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @State private var isMetalSettled = false

    private static let labelSize: CGFloat = 20
    private static let labelTracking: CGFloat = 3
    private static let metalWarmup = Duration.milliseconds(400)

    private struct FacesID: Hashable {
        let content: ResultStubContent
        let width: CGFloat
        let playlist: PlaylistTicket?
    }

    private var edgeStyle: TicketEdgeStyle { TicketEdgeStyle(hasScallops: hasScallops) }

    private var content: ResultStubContent {
        entry.stubContent(display: display, details: details)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaylistTicketPoster(display: display, url: entry.largePosterImageURL, width: width, edgeStyle: edgeStyle)
            if display.isPlayed {
                resultStub.offset(y: PlaylistTicketGeometry.gap(width: width))
            } else {
                pendingStub
            }
        }
        .frame(width: width, height: PlaylistTicketGeometry.frameHeight(width: width, edgeStyle: edgeStyle),
               alignment: .top)
    }

    // MARK: Result stub

    private var resultStub: some View {
        ZStack(alignment: .top) {
            if !isLive || !isMetalSettled {
                PlaylistStubPiece(width: width, edgeStyle: edgeStyle, cut: entry.stubCut(display)) {
                    ResultStubFront(content: content, clipsShape: false)
                        .environment(\.resultStubWidth, width)
                }
            }
            if isLive {
                liveStub
                    .opacity(isStubLifted ? 0 : 1)
                    .task {
                        try? await Task.sleep(for: Self.metalWarmup)
                        isMetalSettled = true
                    }
            }
        }
    }

    private var liveStub: some View {
        let content = content
        return FlipView(size: ResultStubMetrics.size(width: width, edgeStyle: edgeStyle),
                        contentID: FacesID(content: content, width: width, playlist: playlist),
                        menuItems: [],
                        snapshotter: snapshotter,
                        allowsRotation: false) {
            ResultStubFront(content: content)
        } back: {
            ResultStubSetupBack(card: TicketCard(mediaType: entry.mediaType, posterPath: nil, mode: .collection,
                                                 playlist: playlist),
                                setup: RoundSetup(frameCount: PlaylistDetail.frameCount),
                                genreNames: [], edge: content.tearEdge)
        }
        .environment(\.resultStubWidth, width)
        .environment(\.flipTear, FlipTear.round(seed: entry.stubTearSeed, attemptsMade: entry.attemptsUsed,
                                                frameCount: PlaylistDetail.frameCount, outcome: display.outcome,
                                                hasLanded: true))
        .environment(\.flipTearSnaps, true)
    }

    // MARK: Pending stub

    private var pendingStub: some View {
        PlaylistStubPiece(width: width, edgeStyle: edgeStyle, cut: .attached) {
            let zoom = TicketStyle.zoom(forWidth: width)
            VStack(alignment: .leading, spacing: TicketStyle.stubSpacing) {
                PlaylistTicketNumber(number: number, display: display)
                Spacer(minLength: 0)
                Text(display == .next ? "СЛЕДУЮЩИЙ" : "ВПЕРЕДИ")
                    .font(.system(size: Self.labelSize * zoom, weight: .heavy))
                    .tracking(Self.labelTracking * zoom)
                    .foregroundStyle(TicketStyle.placeholderInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(TicketStubFrame(width: width, edgeStyle: edgeStyle))
            .background(TicketStyle.paper)
        }
        .environment(\.colorScheme, .light)
    }
}

#Preview("Раскрытый билет") {
    PlaylistsPreview { playlists in
        if let playlist = playlists.playlists.first,
           let entry = playlist.playableItems.first(where: { $0.state == .completed }) {
            PlaylistBigTicket(entry: entry, display: playlist.display(of: entry), number: 1,
                              playlist: playlists.ticket(id: playlist.id), details: nil, width: 293)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}
