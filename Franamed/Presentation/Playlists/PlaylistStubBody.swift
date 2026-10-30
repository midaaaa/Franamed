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
    private static let pickerGap: CGFloat = 10
    private static let pickerRadius: CGFloat = 8
    private static let pickerStroke = StrokeStyle(lineWidth: 1.4, dash: [5, 4])
    private static let pickerSpacing: CGFloat = 8
    private static let pickerPlusSize: CGFloat = 22
    private static let pickerLabelSize: CGFloat = 11
    private static let pickerTracking: CGFloat = 2.4

    @Environment(\.ticketInk) private var ink

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TicketStubHeader(title: mode.displayName, mediaType: mediaType)
            if playlist == nil {
                picker
            } else {
                content
                TicketPlayCode(caption: caption, serial: serial)
                    .padding(.top, TicketStyle.codeGap)
            }
        }
        .modifier(TicketStubLayout(serial: playlist == nil ? nil : serial))
    }

    private var picker: some View {
        VStack(spacing: Self.pickerSpacing) {
            Image(systemName: "plus")
                .font(.system(size: Self.pickerPlusSize, weight: .medium))
            HStack(spacing: 6) {
                Text("ВЫБРАТЬ")
                    .tracking(Self.pickerTracking)
                Image(systemName: "chevron.right")
            }
            .font(.system(size: Self.pickerLabelSize, weight: .heavy))
            .padding(.leading, Self.pickerTracking)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Self.pickerRadius).strokeBorder(style: Self.pickerStroke)
        }
        .padding(.top, Self.pickerGap)
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
                    .environment(\.colorScheme, ink.isPrint ? .dark : .light)
            }
        }
        .padding(.top, TicketStyle.codeGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caption: String {
        playlist?.isResumable == true ? "ПРОДОЛЖИТЬ" : "ИГРАТЬ"
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
