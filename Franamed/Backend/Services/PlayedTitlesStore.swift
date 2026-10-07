//
//  PlayedTitlesStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import Foundation

actor PlayedTitlesStore {
    private let profile: BackendProfileServiceProtocol
    private let round: BackendRoundServiceProtocol
    private let titlesCache = JSONFileCache<[String: PlayedTitle]>(url: URL.applicationSupportDirectory.appending(path: "played-titles.json"))
    private let pendingCache = JSONFileCache<[PendingFinish]>(url: URL.applicationSupportDirectory.appending(path: "pending-finishes.json"))
    private var titles: [String: PlayedTitle]?
    private lazy var pending: [PendingFinish] = pendingCache.load() ?? []
    private var isSending = false

    init(profile: BackendProfileServiceProtocol, round: BackendRoundServiceProtocol) {
        self.profile = profile
        self.round = round
    }

    func all() async -> [String: PlayedTitle] {
        var result = await loadTitles() ?? [:]
        for finish in pending where result[finish.mediaKey] == nil {
            result[finish.mediaKey] = PlayedTitle(isHidden: false, lastPlayedAt: finish.playedAt)
        }
        return result
    }

    func record(_ finish: PendingFinish) async {
        pending.append(finish)
        pendingCache.save(pending)
        if titles != nil {
            update(finish.mediaKey, to: PlayedTitle(isHidden: false, lastPlayedAt: finish.playedAt))
        }
        await sendPending()
    }

    func sendPending() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }

        while let finish = pending.first {
            guard let result = try? await round.finishCuratedRound(finish) else { return }

            pending.removeFirst()
            pendingCache.save(pending)
            if titles != nil, let played = result.watched.playedTitle {
                update(finish.mediaKey, to: played)
            }
        }
    }

    func reset() async throws {
        await sendPending()
        try await profile.resetWatched(source: nil)
        titles = [:]
        titlesCache.save([:])
    }

    private func loadTitles() async -> [String: PlayedTitle]? {
        if let titles { return titles }
        if let saved = titlesCache.load() {
            titles = saved
            return saved
        }
        guard let watched = try? await profile.watched() else { return nil }
        let restored = watched.reduce(into: [String: PlayedTitle]()) { result, entry in
            result[entry.mediaKey] = entry.playedTitle
        }
        titles = restored
        titlesCache.save(restored)
        return restored
    }

    private func update(_ mediaKey: String, to played: PlayedTitle) {
        titles?[mediaKey] = played
        if let titles { titlesCache.save(titles) }
    }
}
