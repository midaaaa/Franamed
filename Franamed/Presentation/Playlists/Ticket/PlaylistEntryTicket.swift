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
    private static let numberSize: CGFloat = 52
    private static let dotsScale: CGFloat = 4.3
    private static let nextOutline: CGFloat = 6

    private var edgeStyle: TicketEdgeStyle { TicketEdgeStyle(hasScallops: hasScallops) }

    var body: some View {
        Color.clear
            .aspectRatio(PlaylistTicketGeometry.aspectRatio(edgeStyle: edgeStyle), contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    canvas.scaleEffect(proxy.size.width / Self.width, anchor: .topLeading)
                }
                .modifier(Rasterize(isActive: rasterizes))
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
                    .background(TicketStyle.paper)
            }
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
        VStack(spacing: TicketStyle.stubSpacing) {
            PlaylistTicketDots(progress: entry.progress(display), scale: Self.dotsScale)
            Spacer(minLength: 0)
            PlaylistTicketNumber(number: number, display: display, size: Self.numberSize)
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlaylistTicketDots: View {
    let progress: ResultStubProgress
    let scale: CGFloat

    var body: some View {
        ResultStubDots(progress: progress, reservesRing: false)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(maxWidth: .infinity, minHeight: ResultStubDots.compactHeight * scale, alignment: .topLeading)
    }
}

struct PlaylistTicketNumber: View {
    let number: Int
    let display: PlaylistEntryDisplay
    let size: CGFloat

    var body: some View {
        Text(number, format: .number.precision(.integerLength(2)))
            .font(.system(size: size, weight: display == .next ? .heavy : .semibold, design: .monospaced))
            .foregroundStyle(display == .upcoming ? TicketStyle.placeholderInk : Color.black)
    }
}

#Preview("Билеты подборки") {
    PlaylistsPreview { playlists in
        if let playlist = playlists.playlists.first {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(spacing: PlaylistStyle.gridSpacing),
                                         count: PlaylistStyle.gridColumns),
                          spacing: PlaylistStyle.gridSpacing) {
                    ForEach(Array(playlist.playableItems.enumerated()), id: \.element.key) { index, entry in
                        PlaylistEntryTicket(entry: entry, display: playlist.display(of: entry), number: index + 1)
                    }
                }
                .padding()
            }
            .background(Color.black)
        }
    }
}
