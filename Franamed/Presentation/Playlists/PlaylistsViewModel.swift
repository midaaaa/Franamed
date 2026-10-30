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
    var isStampGold = false
    var hasWhiteStamp = false
    var uid: String?
    var isResumable = false

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
    @Published private(set) var stamps: [String: Bool] = [:]
    @Published private(set) var newKeys: [String: Set<String>] = [:]
    @Published private(set) var loadState = LoadState.idle
    @Published private(set) var resumes: [String: PlaylistRoundResume]
    @Published private(set) var emptyPosters: [MediaType: [URL]] = [:]

    private var openedIDs: Set<String> = []
    private var uid: String?
    private var hasRefreshedEmptyPosters = false
    private let store: PlaylistsStore
    private let catalogIndex: CatalogIndexStore
    private let catalog: BackendCatalogServiceProtocol
    private let imageBaseURL: String
    private let defaults: UserDefaults
    private let resumeStore: PlaylistRoundResumes

    private static let lastSeenKey = "playlists.lastSeen"
    private static let emptyPosterCount = 3

    init(backend: Backend = AppFactory.makeBackend(), defaults: UserDefaults = .standard) {
        store = backend.playlistsStore
        catalogIndex = backend.catalogIndex
        catalog = backend.catalog
        imageBaseURL = backend.configuration.imageBaseURL
        self.defaults = defaults
        resumeStore = PlaylistRoundResumes(defaults: defaults)
        resumes = resumeStore.load()
        for mediaType in MediaType.allCases {
            let stored = defaults.stringArray(forKey: Self.emptyPostersKey(mediaType)) ?? []
            emptyPosters[mediaType] = stored.compactMap(URL.init(string:))
        }
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
        guard let playlist = playlist(id: id), playlist.isFinished else { return false }
        guard let isGold = stamps[id] else { return true }
        return !isGold && playlist.completion == .perfect
    }

    func ticket(for mediaType: MediaType) -> PlaylistTicket? {
        selectedIDs[mediaType].flatMap(ticket(id:))
    }

    func ticket(id: String) -> PlaylistTicket? {
        guard let playlist = playlist(id: id) else { return nil }
        return PlaylistTicket(id: playlist.id, title: playlist.title, coverURL: playlist.largeCoverURL,
                              total: playlist.availableCount, answered: playlist.answeredCount,
                              correct: playlist.correctCount, isFinished: playlist.isFinished,
                              stampProgress: hasPendingStamp(id) ? 0 : 1, isStampGold: stamps[id] ?? false,
                              hasWhiteStamp: stamps[id] == false, uid: uid, isResumable: resume(for: id) != nil)
    }

    func resume(for id: String) -> PlaylistRoundResume? {
        guard let resume = resumes[id],
              playlist(id: id)?.items.contains(where: { $0.key == resume.mediaKey }) == true else { return nil }
        return resume
    }

    func nextTearSeed(for id: String) -> UInt64? {
        guard let playlist = playlist(id: id) else { return nil }
        if let unplayed = playlist.items.first(where: { $0.state != .completed }) {
            return unplayed.tearSeed
        }
        return playlist.items
            .filter { $0.wasCorrect == false }
            .min { ($0.playedAt ?? 0, $0.key) < ($1.playedAt ?? 0, $1.key) }?
            .tearSeed
    }

    // MARK: Actions

    func select(_ id: String) {
        guard let playlist = playlist(id: id) else { return }
        selectedIDs[playlist.mediaType] = id
        defaults.set(id, forKey: Self.selectionKey(playlist.mediaType))
        prefetchCover(playlist.largeCoverURL)
    }

    func setResume(_ resume: PlaylistRoundResume?, for id: String) {
        resumes[id] = playlist(id: id)?.completion == .perfect ? nil : resume
        resumeStore.save(resumes)
    }

    func revealStamp(_ id: String) {
        guard let playlist = playlist(id: id) else { return }
        stamps[id] = playlist.completion == .perfect
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
        guard let url else { return }
        if let image = ImageCache.shared.image(for: url) {
            Task.detached(priority: .utility) { await PlaylistPosterFoil.prepare(url: url, image: image) }
            return
        }
        Task {
            guard let image = await FrameDownloads.shared.image(for: url) else { return }
            ImageCache.shared.store(image, for: url)
            Task.detached(priority: .utility) { await PlaylistPosterFoil.prepare(url: url, image: image) }
        }
    }

    // MARK: Loading

    func load() async {
        guard loadState != .loading else { return }
        if playlists.isEmpty {
            await reloadProgress()
            if playlists.isEmpty { loadState = .loading }
        }
        do {
            let contents = try await store.refresh()
            show(contents, index: try await catalogIndex.current())
        } catch {
            loadState = playlists.isEmpty ? .failed : .loaded
        }
        await refreshEmptyPosters()
    }

    func reloadProgress() async {
        let contents = await store.cached()
        guard contents.snapshot != nil, let index = await catalogIndex.cached() else { return }
        show(contents, index: index)
    }

    func reloadPlayable() async {
        _ = try? await catalogIndex.refresh()
        await load()
    }

    private func refreshEmptyPosters() async {
        guard !hasRefreshedEmptyPosters else { return }
        hasRefreshedEmptyPosters = true
        for mediaType in MediaType.allCases {
            guard let items = try? await catalog.items(mediaType: mediaType, filters: MediaFilters(), query: "",
                                                       includeUnapproved: false, limit: Self.emptyPosterCount,
                                                       offset: 0) else { continue }
            let links = items.compactMap { PlaylistAssembly.image($0.posterURL, base: imageBaseURL) }
            guard !links.isEmpty else { continue }
            defaults.set(links, forKey: Self.emptyPostersKey(mediaType))
            let urls = links.compactMap(URL.init(string:))
            if emptyPosters[mediaType] != urls { emptyPosters[mediaType] = urls }
        }
    }

    private func show(_ contents: PlaylistsStore.Contents, index: CatalogIndex) {
        uid = contents.uid
        apply(PlaylistAssembly.details(from: contents, index: index, imageBaseURL: imageBaseURL))
        if loadState != .loaded { loadState = .loaded }
    }

    private func apply(_ next: [PlaylistDetail]) {
        let isFirstLoad = loadState != .loaded
        var seen = lastSeen
        let now = Date().timeIntervalSince1970 * 1000
        for playlist in next where seen[playlist.id] == nil { seen[playlist.id] = now }
        defaults.set(seen, forKey: Self.lastSeenKey)

        if playlists != next { playlists = next }
        let orphans = resumes.keys.filter { id in !next.contains { $0.id == id } }
        if !orphans.isEmpty {
            for id in orphans { resumes[id] = nil }
            resumeStore.save(resumes)
        }
        var nextSelected: [MediaType: String] = [:]
        for mediaType in MediaType.allCases {
            let stored = defaults.string(forKey: Self.selectionKey(mediaType))
            nextSelected[mediaType] = next.first { $0.id == stored && $0.mediaType == mediaType }?.id
        }
        if selectedIDs != nextSelected { selectedIDs = nextSelected }
        var nextStamps: [String: Bool] = [:]
        for playlist in next where playlist.isFinished {
            let isGold = playlist.completion == .perfect
            if isFirstLoad {
                nextStamps[playlist.id] = isGold
            } else if let wasGold = stamps[playlist.id] {
                nextStamps[playlist.id] = wasGold && isGold
            }
        }
        if stamps != nextStamps { stamps = nextStamps }
        let nextNewKeys = Self.newKeys(in: next, seen: seen)
        if newKeys != nextNewKeys { newKeys = nextNewKeys }
    }

    // MARK: Helpers

    private var lastSeen: [String: Double] {
        defaults.dictionary(forKey: Self.lastSeenKey) as? [String: Double] ?? [:]
    }

    private static func selectionKey(_ mediaType: MediaType) -> String {
        "playlists.selected.\(mediaType.rawValue)"
    }

    private static func emptyPostersKey(_ mediaType: MediaType) -> String {
        "playlists.emptyPosters.\(mediaType.rawValue)"
    }

    private static func newKeys(in playlists: [PlaylistDetail], seen: [String: Double]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for playlist in playlists where playlist.answeredCount > 0 {
            let since = seen[playlist.id] ?? .infinity
            let keys = playlist.items
                .filter { $0.state != .completed && ($0.addedAt ?? 0) > since }
                .map(\.key)
            if !keys.isEmpty { result[playlist.id] = Set(keys) }
        }
        return result
    }
}

private extension PlaylistDetail {
    func startedRank(isUpdated: Bool) -> Int {
        if isUpdated { return 0 }
        if isFinished { return 3 }
        return answeredCount > 0 ? 1 : 2
    }
}
