//
//  PlaylistDetailView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct PlaylistDetailView: View {
    @ObservedObject var playlists: PlaylistsViewModel
    let playlistID: String
    @ObservedObject var flight: PlaylistFlightState
    var onLightbox: (AnyView?) -> Void = { _ in }

    @State private var contentWidth: CGFloat = 0
    @State private var isLightboxOpen = false
    @StateObject private var lightboxGrid = PlaylistLightboxGrid()
    @StateObject private var loader = PlaylistTicketLoader()

    private static let closeSettleDelay = Duration.milliseconds(32)

    private var zoom: CGFloat { PlaylistStyle.pageZoom(forWidth: contentWidth) }

    var body: some View {
        if let playlist = playlists.playlist(id: playlistID) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(playlist)
                        grid(playlist)
                        if playlist.availableCount == 0 {
                            Text("Фильмы появятся, когда для них наберутся кадры")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, PlaylistStyle.pageInset(forWidth: contentWidth))
                    .padding(.bottom, 24)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                .onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .global).inset(by: UIEdgeInsets(top: geometry.safeAreaInsets.top, left: 0,
                                                                        bottom: geometry.safeAreaInsets.bottom, right: 0))
                } action: { [lightboxGrid] visible in
                    lightboxGrid.visible = visible
                }
                .onChange(of: lightboxGrid.scrollTarget) { _, target in
                    guard let target else { return }
                    if target.isAnimated {
                        withAnimation(PlaylistLightboxGrid.scrollAnimation) { proxy.scrollTo(target.key, anchor: .center) }
                    } else {
                        proxy.scrollTo(target.key, anchor: .center)
                    }
                    lightboxGrid.didScroll()
                }
            }
        }
    }

    private func openLightbox(_ key: String, in playlist: PlaylistDetail) {
        guard !isLightboxOpen else { return }
        isLightboxOpen = true
        let scrolls = lightboxGrid.reveal(key, isAnimated: true)
        let lightbox = PlaylistTicketLightbox(playlist: playlist, startKey: key,
                                              ticket: playlists.ticket(id: playlist.id), loader: loader,
                                              grid: lightboxGrid, onClosed: closeLightbox)
        Task {
            if scrolls { try? await Task.sleep(for: PlaylistLightboxGrid.scrollDuration) }
            onLightbox(AnyView(lightbox))
        }
    }

    private func closeLightbox() {
        lightboxGrid.hide(nil)
        Task {
            try? await Task.sleep(for: Self.closeSettleDelay)
            isLightboxOpen = false
            onLightbox(nil)
        }
    }

    // MARK: Header

    private func header(_ playlist: PlaylistDetail) -> some View {
        VStack(spacing: 14) {
            PlaylistPosterFan(posters: playlist.folderPosters(count: PlaylistFolderCover.posterCount),
                              isHidden: flight.flyingID == playlist.id, zoom: zoom)
                .onGlobalFrameChange { [flight] in flight.headerFrames[playlist.id] = $0 }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    let added = playlists.addedCount(playlist.id)
                    if added > 0 {
                        Text("ДОПОЛНЕНА · +\(added) \(RussianPlural.form(added, one: "НОВЫЙ", few: "НОВЫХ", many: "НОВЫХ"))")
                            .font(PlaylistStyle.kicker)
                            .tracking(1.5)
                            .foregroundStyle(Accent.reward)
                    }
                    Text(playlist.title)
                        .font(PlaylistStyle.title(zoom: zoom))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                PlaylistProgressRing(playlist: playlist, zoom: zoom)
                    .frame(width: 64 * zoom)
            }
            if let description = playlist.description, !description.isEmpty {
                Text(description)
                    .font(PlaylistStyle.description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: Grid

    private func grid(_ playlist: PlaylistDetail) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: PlaylistStyle.gridSpacing),
                            count: PlaylistStyle.gridColumns(width: contentWidth))
        return LazyVGrid(columns: columns, spacing: PlaylistStyle.gridSpacing) {
            ForEach(Array(playlist.playableItems.enumerated()), id: \.element.key) { index, entry in
                cell(playlist, entry: entry, number: index + 1)
            }
        }
    }

    private func cell(_ playlist: PlaylistDetail, entry: PlaylistEntry, number: Int) -> some View {
        PlaylistEntryTicket(entry: entry, display: playlist.display(of: entry), number: number,
                            isNew: playlists.isNew(entry.key, in: playlist.id))
            .opacity(lightboxGrid.hiddenKey == entry.key ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture { openLightbox(entry.key, in: playlist) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [lightboxGrid] frame in
                lightboxGrid.frames[entry.key] = frame
            }
            .id(entry.key)
    }
}

#Preview("Подборка") {
    PlaylistsPreview { playlists in
        NavigationStack {
            if let playlist = playlists.playlists.first {
                PlaylistDetailView(playlists: playlists, playlistID: playlist.id, flight: PlaylistFlightState())
            }
        }
    }
}
