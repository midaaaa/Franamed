//
//  PlaylistAssembly.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.10.2026.
//

import Foundation

enum PlaylistAssembly {
    static func details(from contents: PlaylistsStore.Contents, index: CatalogIndex, imageBaseURL: String) -> [PlaylistDetail] {
        guard let snapshot = contents.snapshot else { return [] }
        let playableKeys = Set(index.items.map(\.key))
        let answers = Dictionary(grouping: contents.answers?.answers ?? [], by: \.playlistId)

        return snapshot.playlists.compactMap { playlist in
            let answered = Dictionary((answers[playlist.id] ?? []).map { ($0.mediaKey, $0) }) { first, _ in first }
            var items = playlist.items
                .filter { playableKeys.contains($0.key) }
                .map { item in
                    entry(item, answer: answered[item.key], imageBaseURL: imageBaseURL,
                          tearSeed: contents.uid.map { FlipTear.seed(uid: $0, playlistID: playlist.id, mediaKey: item.key) })
                }
            guard !items.isEmpty else { return nil }
            if !playlist.orderByCurator, let uid = contents.uid {
                items.sort { playerOrderRank(uid: uid, playlistId: playlist.id, mediaKey: $0.key)
                    < playerOrderRank(uid: uid, playlistId: playlist.id, mediaKey: $1.key) }
            }
            let folderPosters = playlist.folderPosters.compactMap { image($0, base: imageBaseURL) }
            let cover = image(playlist.coverImageURL, base: imageBaseURL) ?? folderPosters.first
            return PlaylistDetail(id: playlist.id, title: playlist.title, description: playlist.description,
                                  coverImageURL: cover, mediaType: playlist.mediaType, createdAt: playlist.createdAt, items: items,
                                  folderPosters: folderPosters, orderByCurator: playlist.orderByCurator)
        }
    }

    static func playerOrderRank(uid: String, playlistId: String, mediaKey: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for scalar in "\(uid):\(playlistId):\(mediaKey)".unicodeScalars {
            hash ^= scalar.value
            hash = hash &* 16_777_619
        }
        return hash
    }

    private static func entry(_ item: PlaylistsSnapshot.Item, answer: PlaylistAnswers.Answer?,
                              imageBaseURL: String, tearSeed: UInt64?) -> PlaylistEntry {
        PlaylistEntry(key: item.key, title: item.title, releaseYear: item.releaseYear,
                      posterURL: image(item.posterURL, base: imageBaseURL),
                      state: answer == nil ? .notStarted : .completed, attemptsUsed: answer?.attemptsUsed ?? 0,
                      wasCorrect: answer?.wasCorrect, addedAt: item.addedAt,
                      playedAt: answer?.updatedAt, tearSeed: tearSeed)
    }

    private static func image(_ path: String?, base: String) -> String? {
        guard let path else { return nil }
        if path.hasPrefix("http") { return path }
        return "\(base)\(TMDBImageSize.smallPath)\(path)"
    }
}
