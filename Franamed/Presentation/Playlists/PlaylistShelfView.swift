//
//  PlaylistShelfView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import Combine
import SwiftUI

@MainActor
final class PlaylistShelfQuery: ObservableObject {
    @Published var text = ""
}

struct PlaylistShelfView: View {
    @ObservedObject var playlists: PlaylistsViewModel
    let mediaType: MediaType
    @ObservedObject var flight: PlaylistFlightState
    @ObservedObject var query: PlaylistShelfQuery
    let revealID: String?
    let onOpen: (String) -> Void

    @AppStorage(PlaylistSort.storageKey) private var sort = PlaylistSort.started
    @State private var isRevealed = false
    @State private var order: [String] = []

    private var items: [PlaylistDetail] {
        let found = playlists.shelf(for: mediaType, query: query.text, sort: sort)
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return found.enumerated()
            .sorted { (position[$0.element.id] ?? order.count, $0.offset) < (position[$1.element.id] ?? order.count, $1.offset) }
            .map(\.element)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .onAppear {
                    guard !isRevealed else { return }
                    isRevealed = true
                    if let revealID { proxy.scrollTo(revealID, anchor: .center) }
                }
        }
        .onChange(of: sort, initial: true) { pinOrder() }
        .onChange(of: playlists.loadState) { if order.isEmpty { pinOrder() } }
    }

    private func pinOrder() {
        order = playlists.shelf(for: mediaType, query: "", sort: sort).map(\.id)
    }

    @ViewBuilder
    private var content: some View {
        if playlists.loadState == .loading, playlists.playlists(for: mediaType).isEmpty {
            ProgressView()
                .padding(.top, 120)
        } else if playlists.loadState == .failed {
            ContentUnavailableView {
                Label("Подборки не загрузились", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Проверьте интернет и попробуйте ещё раз.")
            } actions: {
                Button("Повторить") { Task { await playlists.load() } }
                    .buttonStyle(.glassProminent)
            }
            .padding(.top, 80)
        } else if playlists.playlists(for: mediaType).isEmpty {
            ContentUnavailableView(
                "Подборок пока нет",
                systemImage: "film.stack",
                description: Text("Подборки \(mediaType == .movie ? "фильмов" : "сериалов") появятся позже")
            )
            .padding(.top, 80)
        } else if items.isEmpty {
            ContentUnavailableView.search(text: query.text)
                .padding(.top, 80)
        } else {
            grid
        }
    }

    private var grid: some View {
        let columns = PlaylistStyle.shelfColumns
        let items = items
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        return Grid(alignment: .top, horizontalSpacing: PlaylistStyle.shelfSpacing, verticalSpacing: 24) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { item($0) }
                    if row.count < columns {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .gridCellUnsizedAxes(.vertical)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(.snappy, value: items.map(\.id))
    }

    private func item(_ playlist: PlaylistDetail) -> some View {
        PlaylistShelfItem(playlist: playlist,
                          isSelected: playlists.selectedID(for: mediaType) == playlist.id,
                          addedCount: playlists.addedCount(playlist.id),
                          track: flight.flyingID == playlist.id ? flight.track : nil,
                          isOpen: flight.openID == playlist.id,
                          folderOrigin: flight.folderFrames[playlist.id]?.origin ?? .zero,
                          actions: actions(for: playlist),
                          onTap: { onOpen(playlist.id) },
                          onFolderFrame: { [flight] in flight.folderFrames[playlist.id] = $0 })
            .onGlobalFrameChange { [flight] in flight.cellFrames[playlist.id] = $0 }
    }

    private func actions(for playlist: PlaylistDetail) -> [PlaylistMenuAction] {
        var actions: [PlaylistMenuAction] = []
        if playlists.selectedID(for: mediaType) != playlist.id {
            actions.append(PlaylistMenuAction(title: "Выбрать", systemImage: "checkmark.circle") {
                playlists.select(playlist.id)
            })
        }
        actions.append(PlaylistMenuAction(title: "Подробнее", systemImage: "info.circle") { onOpen(playlist.id) })
        return actions
    }
}

private struct PlaylistShelfItem: View {
    let playlist: PlaylistDetail
    let isSelected: Bool
    let addedCount: Int
    let track: PlaylistPosterTrack?
    let isOpen: Bool
    let folderOrigin: CGPoint
    let actions: [PlaylistMenuAction]
    let onTap: () -> Void
    let onFolderFrame: (CGRect) -> Void

    @State private var isLifted = false

    private static let liftUp = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private static let liftDown = Animation.spring(response: 0.35, dampingFraction: 0.62)

    var body: some View {
        PlaylistTrackedPosters(track: track ?? .idle, origin: folderOrigin) { slots, isCopyShown in
            cell(isLifted: isLifted || isOpen || track != nil, posterOverride: slots, hidesPosters: isCopyShown,
                 onFolderFrame: onFolderFrame)
        }
        .overlay {
            PlaylistShelfMenu(title: playlist.title,
                              preview: AnyView(cell(isLifted: true).padding(4)),
                              actions: actions,
                              onTap: onTap,
                              onLift: { isUp in withAnimation(isUp ? Self.liftUp : Self.liftDown) { isLifted = isUp } })
        }
    }

    private func cell(isLifted: Bool, posterOverride: [PlaylistPosterSlot]? = nil, hidesPosters: Bool = false,
                      onFolderFrame: ((CGRect) -> Void)? = nil) -> some View {
        PlaylistCoverCell(playlist: playlist, isSelected: isSelected, addedCount: addedCount, isLifted: isLifted,
                          posterOverride: posterOverride, hidesPosters: hidesPosters, onFolderFrame: onFolderFrame)
    }
}

private struct PlaylistTrackedPosters<Content: View>: View {
    @ObservedObject var track: PlaylistPosterTrack
    let origin: CGPoint
    @ViewBuilder let content: ([PlaylistPosterSlot]?, Bool) -> Content

    var body: some View {
        content(track.slots?.map { $0.offset(by: CGPoint(x: -origin.x, y: -origin.y)) }, track.isCopyShown)
    }
}
