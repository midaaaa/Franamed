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

    @State private var focusedKey: String?

    var body: some View {
        if let playlist = playlists.playlist(id: playlistID) {
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
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Header

    private func header(_ playlist: PlaylistDetail) -> some View {
        VStack(spacing: 14) {
            PlaylistPosterFan(posters: playlist.folderPosters(count: PlaylistFolderCover.posterCount),
                              isHidden: flight.flyingID == playlist.id)
                .onGlobalFrameChange { [flight] in flight.headerFrames[playlist.id] = $0 }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    let added = playlists.addedCount(playlist.id)
                    if added > 0 {
                        Text("ДОПОЛНЕНА · +\(added) \(RussianPlural.form(added, one: "НОВЫЙ", few: "НОВЫХ", many: "НОВЫХ"))")
                            .font(PlaylistStyle.kicker)
                            .tracking(1.5)
                            .foregroundStyle(Accent.reward)
                    }
                    Text(playlist.title)
                        .font(PlaylistStyle.title)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                PlaylistProgressRing(playlist: playlist)
                    .frame(width: 64)
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
        let columns = PlaylistStyle.gridColumns
        let entries = playlist.playableItems
        let rows = stride(from: 0, to: entries.count, by: columns).map { start in
            Array(start..<min(start + columns, entries.count))
        }
        return Grid(horizontalSpacing: PlaylistStyle.gridSpacing, verticalSpacing: PlaylistStyle.gridSpacing) {
            ForEach(rows, id: \.first) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        if column < row.count {
                            cell(playlist, entry: entries[row[column]], number: row[column] + 1)
                        } else {
                            Color.clear.aspectRatio(PlaylistStyle.posterAspectRatio, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ playlist: PlaylistDetail, entry: PlaylistEntry, number: Int) -> some View {
        let display = playlist.display(of: entry)
        return PlaylistEntryCell(display: display, number: number, posterURL: entry.posterImageURL,
                                 isNew: playlists.isNew(entry.key, in: playlist.id))
            .contentShape(Rectangle())
            .onTapGesture { focusedKey = entry.key }
            .popover(isPresented: focusBinding(entry.key), arrowEdge: .bottom) {
                PlaylistEntryCard(entry: entry, display: display, number: number)
                    .frame(maxWidth: WindowMetrics.size.width - 32, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .presentationCompactAdaptation(.popover)
            }
            .modifier(PlaylistPosterPreview(entry: entry))
    }

    private func focusBinding(_ key: String) -> Binding<Bool> {
        Binding {
            focusedKey == key
        } set: { isPresented in
            if !isPresented, focusedKey == key { focusedKey = nil }
        }
    }
}

private struct PlaylistEntryCard: View {
    let entry: PlaylistEntry
    let display: PlaylistEntryDisplay
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isAnswered ? entry.title : "Фильм \(number)")
                .font(.system(.headline, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let color = resultColor {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var isAnswered: Bool { entry.state == .completed }

    private var resultColor: Color? {
        switch display {
        case .guessed: PlaylistStyle.hit
        case .missed: PlaylistStyle.miss
        case .next, .upcoming: nil
        }
    }

    private var detail: String {
        let result = switch display {
        case .guessed(let frame): "угадан с \(frame)-го кадра"
        case .missed: "не угадан"
        case .next: "следующий"
        case .upcoming: "впереди"
        }
        guard isAnswered, let year = entry.releaseYear else { return result }
        return "\(year) · \(result)"
    }
}

private struct PlaylistPosterPreview: ViewModifier {
    let entry: PlaylistEntry

    func body(content: Content) -> some View {
        if entry.state == .completed {
            content.contextMenu {
                Button("Скопировать название", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = entry.title
                }
            } preview: {
                VStack(alignment: .leading, spacing: 8) {
                    Color.clear
                        .aspectRatio(PlaylistStyle.posterAspectRatio, contentMode: .fit)
                        .overlay { CachedRemoteImage(url: entry.largePosterImageURL) }
                        .clipped()
                    Text(entry.title)
                        .font(.system(.headline, design: .serif))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
                .frame(width: 280)
            }
        } else {
            content
        }
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
