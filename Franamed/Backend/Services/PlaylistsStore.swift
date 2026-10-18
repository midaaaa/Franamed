//
//  PlaylistsStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 18.10.2026.
//

import Foundation

actor PlaylistsStore {
    struct Contents: Sendable {
        let snapshot: PlaylistsSnapshot?
        let answers: PlaylistAnswers?
        let uid: String?
    }

    private struct SavedAnswers: Codable {
        let uid: String
        var answers: PlaylistAnswers
    }

    private let service: BackendPlaylistServiceProtocol
    private let tokens: BackendTokenStore
    private let playedTitles: PlayedTitlesStore
    private let latestVersion: @Sendable () -> String?
    private let snapshotCache = JSONFileCache<PlaylistsSnapshot>(url: URL.applicationSupportDirectory.appending(path: "playlists-snapshot.json"))
    private let answersCache = JSONFileCache<SavedAnswers>(url: URL.applicationSupportDirectory.appending(path: "playlist-answers.json"))

    private var snapshot: PlaylistsSnapshot?
    private var saved: SavedAnswers?
    private var isLoadedFromDisk = false
    private var isSnapshotCheckedThisLaunch = false
    private var areAnswersCheckedThisLaunch = false
    private var refreshing: Task<Contents, Error>?

    init(service: BackendPlaylistServiceProtocol, tokens: BackendTokenStore, playedTitles: PlayedTitlesStore,
         latestVersion: @escaping @Sendable () -> String?) {
        self.service = service
        self.tokens = tokens
        self.playedTitles = playedTitles
        self.latestVersion = latestVersion
    }

    private var contents: Contents {
        Contents(snapshot: snapshot, answers: saved?.answers, uid: saved?.uid)
    }

    // MARK: Reading

    func cached() -> Contents {
        loadFromDisk()
        return contents
    }

    func refresh() async throws -> Contents {
        if let refreshing { return try await refreshing.value }
        let task = Task { try await performRefresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> Contents {
        loadFromDisk()
        try await refreshSnapshot()
        try await refreshAnswers()
        return contents
    }

    private func refreshSnapshot() async throws {
        if let snapshot, isSnapshotCheckedThisLaunch, latestVersion().map({ $0 == snapshot.version }) ?? true {
            return
        }
        do {
            if let fresh = try await service.snapshot(ifNoneMatch: snapshot?.version) {
                snapshot = fresh
                snapshotCache.save(fresh)
            }
            isSnapshotCheckedThisLaunch = true
        } catch {
            guard snapshot != nil else { throw error }
        }
    }

    private func refreshAnswers() async throws {
        let uid = await tokens.user?.uid
        if let saved, let uid, saved.uid != uid {
            self.saved = nil
            areAnswersCheckedThisLaunch = false
        }
        if saved != nil, areAnswersCheckedThisLaunch { return }

        await playedTitles.sendPending()
        if saved != nil, await playedTitles.hasPending { return }

        do {
            let fresh = try await service.answers()
            guard let uid = await tokens.user?.uid else { return }
            let next = SavedAnswers(uid: uid, answers: fresh)
            saved = next
            answersCache.save(next)
            areAnswersCheckedThisLaunch = true
        } catch {
            guard saved != nil else { throw error }
        }
    }

    // MARK: Writing

    func record(playlistId: String, mediaKey: String, attemptsUsed: Int, wasCorrect: Bool, at date: Date) async {
        loadFromDisk()
        guard let uid = await tokens.user?.uid ?? saved?.uid else { return }
        var next = saved.flatMap { $0.uid == uid ? $0 : nil }
            ?? SavedAnswers(uid: uid, answers: PlaylistAnswers(answers: [], completions: []))

        let playedAt = date.timeIntervalSince1970 * 1000
        if let index = next.answers.answers.firstIndex(where: { $0.playlistId == playlistId && $0.mediaKey == mediaKey }) {
            var answer = next.answers.answers[index]
            if answer.wasCorrect != true { answer.attemptsUsed = attemptsUsed }
            answer.wasCorrect = answer.wasCorrect == true || wasCorrect
            answer.updatedAt = playedAt
            next.answers.answers[index] = answer
        } else {
            next.answers.answers.append(PlaylistAnswers.Answer(playlistId: playlistId, mediaKey: mediaKey, attemptsUsed: attemptsUsed,
                                                               wasCorrect: wasCorrect, updatedAt: playedAt))
        }
        saved = next
        answersCache.save(next)
    }

    // MARK: Disk

    private func loadFromDisk() {
        guard !isLoadedFromDisk else { return }
        isLoadedFromDisk = true
        snapshot = snapshot ?? snapshotCache.load()
        saved = saved ?? answersCache.load()
    }
}
