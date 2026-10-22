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
    var onOpenPicker: () -> Void = {}
    var onStart: () -> Void = {}

    private static let ringSide: CGFloat = 64
    private static let stampScale: CGFloat = 1
    private static let stampOverhang: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: TicketStyle.stubSpacing) {
            Text(mode.displayName)
                .font(TicketStyle.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button(action: onOpenPicker) {
                content.contentShape(Rectangle())
            }
            .frame(maxHeight: .infinity)
            startButton
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        HStack(spacing: 16) {
            name
            if let playlist {
                PlaylistProgressRing(ticket: playlist, stampScale: Self.stampScale)
                    .frame(width: Self.ringSide)
                    .padding(.trailing, Self.stampOverhang)
                    .environment(\.colorScheme, .light)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var name: some View {
        let title = playlist?.title ?? "Выберите подборку"
        return ViewThatFits(in: .horizontal) {
            nameText(title, font: .system(size: 24, weight: .semibold, design: .serif), lines: 1)
                .fixedSize()
            nameText(title, font: .system(size: 20, weight: .semibold, design: .serif), lines: 3)
        }
        .foregroundStyle(playlist == nil ? TicketStyle.placeholderInk : Color.black)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nameText(_ title: String, font: Font, lines: Int) -> some View {
        Text(title)
            .font(font)
            .lineLimit(lines)
            .minimumScaleFactor(TicketStyle.minimumScale)
            .multilineTextAlignment(.leading)
    }

    private var startButton: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: onStart) {
                TicketBarcodeView(mediaType: mediaType, mode: mode)
                    .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("Корешок подборки: пусто и все подборки") {
    PlaylistsPreview { playlists in
        ScrollView {
            VStack(spacing: 16) {
                ForEach([nil] + playlists.playlists.map(\.id), id: \.self) { id in
                    PlaylistStubBody(mediaType: .movie, mode: .collection, playlist: id.flatMap(playlists.ticket(id:)))
                        .modifier(TicketStubFrame(width: 300, edgeStyle: .scalloped))
                        .background(TicketStyle.paper)
                }
            }
            .padding()
        }
        .background(Color.black)
    }
}
