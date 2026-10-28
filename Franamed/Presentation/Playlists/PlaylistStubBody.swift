//
//  PlaylistStubBody.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct PlaylistStubBody: View {
    let mediaType: MediaType
    let mode: TicketGameMode
    let playlist: PlaylistTicket?

    private static let ringSide: CGFloat = 64
    private static let stampScale: CGFloat = 1
    private static let stampOverhang: CGFloat = 10
    private static let nameSize: CGFloat = 20
    private static let nameLines = 4
    private static let nameMinimumScale: CGFloat = 0.6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TicketStubHeader(title: mode.displayName, media: mediaType.displayName)
            content
            TicketPlayCode(caption: caption, serial: serial)
                .padding(.top, TicketStyle.codeGap)
        }
        .modifier(TicketStubLayout(serial: serial))
    }

    private var content: some View {
        HStack(spacing: 10) {
            Text(playlist?.title ?? "Выберите подборку")
                .font(.system(size: Self.nameSize, weight: playlist == nil ? .medium : .semibold))
                .lineLimit(Self.nameLines)
                .minimumScaleFactor(Self.nameMinimumScale)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let playlist {
                PlaylistProgressRing(ticket: playlist, stampScale: Self.stampScale)
                    .frame(width: Self.ringSide)
                    .padding(.trailing, Self.stampOverhang)
                    .environment(\.colorScheme, .light)
            }
        }
        .padding(.top, TicketStyle.codeGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caption: String {
        guard let playlist else { return "ВЫБРАТЬ ПОДБОРКУ" }
        return playlist.isResumable ? "ПРОДОЛЖИТЬ" : "ИГРАТЬ"
    }

    private var serial: String {
        mode.serial(mediaType: mediaType)
    }
}

#Preview("Корешок подборки: пусто и все подборки") {
    PlaylistsPreview { playlists in
        ScrollView {
            VStack(spacing: 16) {
                ForEach([nil] + playlists.playlists.map(\.id), id: \.self) { id in
                    PlaylistStubBody(mediaType: .movie, mode: .collection, playlist: id.flatMap(playlists.ticket(id:)))
                        .modifier(TicketStubFrame(width: 293, edgeStyle: .scalloped))
                        .background(TicketStyle.paper)
                }
            }
            .padding()
        }
        .background(Color.black)
    }
}
