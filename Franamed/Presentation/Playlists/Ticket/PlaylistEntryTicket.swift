//
//  PlaylistEntryTicket.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import SwiftUI

struct PlaylistEntryTicket: View {
    let entry: PlaylistEntry
    let display: PlaylistEntryDisplay
    let number: Int
    var isNew = false
    var rasterizes = true

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false

    private static let width = TicketStyle.referenceWidth
    private static let nextOutline: CGFloat = 6

    private static var bleed: CGFloat {
        PlaylistTicketGeometry.ripSeparation(width: width) + nextOutline
    }

    private var edgeStyle: TicketEdgeStyle { TicketEdgeStyle(hasScallops: hasScallops) }
    private var ink: TicketInk { .stub(for: entry.mediaType) }

    var body: some View {
        Color.clear
            .aspectRatio(PlaylistTicketGeometry.aspectRatio(edgeStyle: edgeStyle), contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    let scale = proxy.size.width / Self.width
                    let bleed = Self.bleed * scale
                    canvas.scaleEffect(scale, anchor: .topLeading)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .padding(bleed)
                        .modifier(Rasterize(isActive: rasterizes))
                        .padding(-bleed)
                }
            }
    }

    private var canvas: some View {
        let width = Self.width
        return VStack(spacing: 0) {
            PlaylistTicketPoster(display: display, url: entry.posterImageURL, width: width, edgeStyle: edgeStyle)
                .overlay(alignment: .topLeading) {
                    if isNew { newBadge }
                }
            PlaylistStubPiece(width: width, edgeStyle: edgeStyle, cut: entry.stubCut(display)) {
                stub
                    .modifier(TicketStubFrame(width: width, edgeStyle: edgeStyle))
                    .background(ink.paper)
            }
            .environment(\.ticketInk, ink)
            .environment(\.flipPaperCore, ink.core)
            .offset(y: display.isPlayed ? PlaylistTicketGeometry.gap(width: width) : 0)
        }
        .frame(width: width, height: PlaylistTicketGeometry.frameHeight(width: width, edgeStyle: edgeStyle),
               alignment: .top)
        .overlay(alignment: .top) {
            if display == .next {
                PlaylistTicketGeometry.shape(width: width, edgeStyle: edgeStyle, isPerforated: false)
                    .stroke(.primary, style: StrokeStyle(lineWidth: Self.nextOutline, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: PlaylistTicketGeometry.height(width: width, edgeStyle: edgeStyle))
            }
        }
    }

    private var newBadge: some View {
        Text("NEW")
            .font(.system(size: 36, weight: .heavy))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(.white, in: Capsule())
            .foregroundStyle(.black)
            .padding(14)
    }

    private var stub: some View {
        PlaylistTicketNumber(number: number, display: display)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PlaylistTicketNumber: View {
    let number: Int
    let display: PlaylistEntryDisplay

    private static let size: CGFloat = 64
    private static let longSize: CGFloat = 48

    @Environment(\.ticketInk) private var ink

    var body: some View {
        Text(number, format: .number.precision(.integerLength(2)))
            .font(.system(size: number < 100 ? Self.size : Self.longSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(display == .upcoming ? ink.placeholder : ink.ink)
    }
}

#Preview("Билеты подборки") {
    PlaylistsPreview { playlists in
        if let playlist = playlists.playlists.first {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(spacing: PlaylistStyle.gridSpacing),
                                         count: PlaylistStyle.gridColumns),
                          spacing: PlaylistStyle.gridSpacing) {
                    ForEach(Array(playlist.items.enumerated()), id: \.element.key) { index, entry in
                        PlaylistEntryTicket(entry: entry, display: playlist.display(of: entry), number: index + 1)
                    }
                }
                .padding()
            }
            .background(Color.black)
        }
    }
}
