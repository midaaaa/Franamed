//
//  PlaylistsViewModel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import Combine
import UIKit

struct PlaylistTicket: Hashable {
    let id: String
    let title: String
    let coverURL: URL?
    let total: Int
    let answered: Int
    let correct: Int
    let isFinished: Bool
    var stampProgress: Double

    var isPerfect: Bool { correct >= total }
}

enum PlaylistSort: String, CaseIterable {
    case started
    case newest
    case title

    static let storageKey = "playlists.sort"

    var title: String {
        switch self {
        case .started: "Сначала начатые"
        case .newest: "Сначала новые"
        case .title: "По названию"
        }
    }
}

@MainActor
final class PlaylistsViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var playlists: [PlaylistDetail] = []
    @Published private(set) var selectedIDs: [MediaType: String] = [:]
    @Published private(set) var stampedIDs: Set<String> = []
    @Published private(set) var newKeys: [String: Set<String>] = [:]
    @Published private(set) var loadState = LoadState.idle

    private var openedIDs: Set<String> = []
    private let service: BackendPlaylistServiceProtocol
    private let imageBaseURL: String
    private let defaults: UserDefaults

    private static let lastSeenKey = "playlists.lastSeen"

    init(backend: Backend = AppFactory.makeBackend(), defaults: UserDefaults = .standard) {
        service = backend.playlists
        imageBaseURL = backend.configuration.imageBaseURL
        self.defaults = defaults
    }

    // MARK: Queries

    func playlist(id: String) -> PlaylistDetail? {
        playlists.first { $0.id == id }
    }

    func playlists(for mediaType: MediaType) -> [PlaylistDetail] {
        playlists.filter { $0.mediaType == mediaType }
    }

    func shelf(for mediaType: MediaType, query: String, sort: PlaylistSort) -> [PlaylistDetail] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let found = playlists(for: mediaType).filter {
            trimmed.isEmpty || $0.title.localizedCaseInsensitiveContains(trimmed)
        }
        switch sort {
        case .newest:
            return found
        case .title:
            return found.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .started:
            return found.enumerated()
                .sorted { ($0.element.startedRank(isUpdated: addedCount($0.element.id) > 0), $0.offset)
                    < ($1.element.startedRank(isUpdated: addedCount($1.element.id) > 0), $1.offset) }
                .map(\.element)
        }
    }

    func selectedID(for mediaType: MediaType) -> String? {
        selectedIDs[mediaType]
    }

    func isSelected(_ id: String) -> Bool {
        selectedIDs.values.contains(id)
    }

    func addedCount(_ id: String) -> Int {
        newKeys[id]?.count ?? 0
    }

    func isNew(_ key: String, in id: String) -> Bool {
        newKeys[id]?.contains(key) == true
    }

    func hasPendingStamp(_ id: String) -> Bool {
        playlist(id: id)?.isFinished == true && !stampedIDs.contains(id)
    }

    func ticket(for mediaType: MediaType) -> PlaylistTicket? {
        selectedIDs[mediaType].flatMap(ticket(id:))
    }

    func ticket(id: String) -> PlaylistTicket? {
        guard let playlist = playlist(id: id) else { return nil }
        return PlaylistTicket(id: playlist.id, title: playlist.title, coverURL: playlist.largeCoverURL,
                              total: playlist.availableCount, answered: playlist.answeredCount,
                              correct: playlist.correctCount, isFinished: playlist.isFinished,
                              stampProgress: stampedIDs.contains(id) ? 1 : 0)
    }

    // MARK: Actions

    func select(_ id: String) {
        guard let playlist = playlist(id: id) else { return }
        selectedIDs[playlist.mediaType] = id
        defaults.set(id, forKey: Self.selectionKey(playlist.mediaType))
        prefetchCover(playlist.largeCoverURL)
    }

    func revealStamp(_ id: String) {
        stampedIDs.insert(id)
    }

    func noteOpened(_ id: String) {
        openedIDs.insert(id)
    }

    func markOpenedSeen() {
        var seen = lastSeen
        let now = Date().timeIntervalSince1970 * 1000
        for id in openedIDs { seen[id] = now }
        openedIDs = []
        defaults.set(seen, forKey: Self.lastSeenKey)
        newKeys = Self.newKeys(in: playlists, seen: seen)
    }

    private func prefetchCover(_ url: URL?) {
        guard let url, ImageCache.shared.image(for: url) == nil else { return }
        Task {
            guard let image = await FrameDownloads.shared.image(for: url) else { return }
            ImageCache.shared.store(image, for: url)
        }
    }

    // MARK: Loading

    func load() async {
        guard loadState != .loading else { return }
        if playlists.isEmpty { loadState = .loading }
        do {
            let list = try await service.playlists(mediaType: nil)
            let details = try await withThrowingTaskGroup(of: (Int, PlaylistDetail).self) { [service] group in
                for (index, playlist) in list.enumerated() {
                    group.addTask { (index, try await service.playlist(id: playlist.id)) }
                }
                var found: [(Int, PlaylistDetail)] = []
                for try await pair in group { found.append(pair) }
                return found.sorted { $0.0 < $1.0 }.map(\.1)
            }
            apply(details.map(resolvingImages))
            loadState = .loaded
        } catch {
            loadState = playlists.isEmpty ? .failed : .loaded
        }
    }

    func refresh(_ id: String) async {
        guard let detail = try? await service.playlist(id: id) else { return }
        var next = playlists
        if let index = next.firstIndex(where: { $0.id == id }) {
            next[index] = resolvingImages(detail)
        } else {
            next.append(resolvingImages(detail))
        }
        apply(next)
    }

    private func apply(_ next: [PlaylistDetail]) {
        let wasFinished = Set(playlists.filter(\.isFinished).map(\.id))
        let isFirstLoad = loadState != .loaded
        var seen = lastSeen
        let now = Date().timeIntervalSince1970 * 1000
        for playlist in next where seen[playlist.id] == nil { seen[playlist.id] = now }
        defaults.set(seen, forKey: Self.lastSeenKey)

        playlists = next
        for mediaType in MediaType.allCases {
            let stored = defaults.string(forKey: Self.selectionKey(mediaType))
            selectedIDs[mediaType] = next.first { $0.id == stored && $0.mediaType == mediaType }?.id
        }
        let finished = Set(next.filter(\.isFinished).map(\.id))
        stampedIDs = isFirstLoad ? finished : stampedIDs.union(wasFinished).intersection(finished)
        newKeys = Self.newKeys(in: next, seen: seen)
    }

    // MARK: Helpers

    private var lastSeen: [String: Double] {
        defaults.dictionary(forKey: Self.lastSeenKey) as? [String: Double] ?? [:]
    }

    private static func selectionKey(_ mediaType: MediaType) -> String {
        "playlists.selected.\(mediaType.rawValue)"
    }

    private static func newKeys(in playlists: [PlaylistDetail], seen: [String: Double]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for playlist in playlists where playlist.answeredCount > 0 {
            let since = seen[playlist.id] ?? .infinity
            let keys = playlist.playableItems
                .filter { $0.state != .completed && ($0.addedAt ?? 0) > since }
                .map(\.key)
            if !keys.isEmpty { result[playlist.id] = Set(keys) }
        }
        return result
    }

    private func resolvingImages(_ detail: PlaylistDetail) -> PlaylistDetail {
        let items = detail.items.filter { $0.isPlayable || $0.state == .completed }.map { item in
            PlaylistEntry(key: item.key, title: item.title, releaseYear: item.releaseYear,
                          posterURL: resolvedImage(item.posterURL), approvedImages: item.approvedImages,
                          state: item.state, attemptsUsed: item.attemptsUsed, wasCorrect: item.wasCorrect,
                          playable: item.playable, addedAt: item.addedAt)
        }
        return PlaylistDetail(id: detail.id, title: detail.title, description: detail.description,
                              coverImageURL: resolvedImage(detail.coverImageURL ?? detail.folderPosters?.first),
                              mediaType: detail.mediaType, source: detail.source, allowUncurated: detail.allowUncurated,
                              published: detail.published, createdAt: detail.createdAt, progress: detail.progress,
                              items: items, folderPosters: detail.folderPosters?.compactMap(resolvedImage),
                              orderByCurator: detail.orderByCurator)
    }

    private func resolvedImage(_ path: String?) -> String? {
        guard let path else { return nil }
        if path.hasPrefix("http") { return path }
        return "\(imageBaseURL)\(TMDBImageSize.smallPath)\(path)"
    }
}

private extension PlaylistDetail {
    func startedRank(isUpdated: Bool) -> Int {
        if isUpdated { return 0 }
        if isFinished { return 3 }
        return answeredCount > 0 ? 1 : 2
    }
}
