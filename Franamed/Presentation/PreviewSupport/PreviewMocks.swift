//
//  PreviewMocks.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

#if DEBUG
struct PreviewMediaFacade: MediaFacadeProtocol {
    func searchMedia(mediaType: MediaType, query: String, language: String) async throws -> [MediaItem] {[
        MediaItem(id: 1, mediaType: mediaType, title: "Movie 1", originalTitle: "Movie 1", releaseDate: "2025-04-05", overview: "Preview overview 1"),
        MediaItem(id: 2, mediaType: mediaType, title: "Movie 2", originalTitle: "Movie 2", releaseDate: "2026-04-05", overview: "Preview overview 2")
    ]}

    func fetchRandomMediaItemAndBackdrops(mediaType: MediaType, filters: MediaFilters, frameCount: Int) async throws -> MediaItemWithBackdrops {
        let randomId = Int.random(in: 1...1_000_000)
        return MediaItemWithBackdrops(
            item: MediaItem(id: randomId, mediaType: mediaType, title: "Preview Movie", originalTitle: "Preview Movie", releaseDate: "2024-01-01", overview: "Preview overview"),
            backdrops: (1...6).map { Backdrop(filePath: "https://picsum.photos/seed/backdrop\($0)/1280/720") }
        )
    }

    func fetchGenres(mediaType: MediaType) async throws -> [Genre] {
        [
            Genre(id: 1, name: "Драма"),
            Genre(id: 2, name: "Комедия"),
            Genre(id: 3, name: "Фантастика")
        ]
    }

    func fetchResultsCount(mediaType: MediaType, filters: MediaFilters) async throws -> Int {
        124
    }

    func fetchCuratedRound(mediaType: MediaType, filters: MediaFilters, frameCount: Int, excludeWatched: Bool) async throws -> RoundPayload {
        let key = "\(mediaType.rawValue)_\(Int.random(in: 1...1_000_000))"

        return RoundPayload(
            pool: .curated,
            date: nil,
            playlistId: nil,
            item: CuratedItem(
                key: key,
                tmdbId: 603,
                mediaType: mediaType,
                title: "Preview Movie",
                originalTitle: "Preview Movie",
                releaseYear: 2024,
                originalLanguage: "en",
                popularity: 42,
                posterURL: nil,
                status: "approved",
                genreIds: [1, 2],
                totalImages: 12,
                reviewedImages: 12,
                approvedImages: 8,
                adminFinalized: true,
                finalizedAt: nil,
                lastSyncedAt: nil
            ),
            frames: (1...frameCount).map { index in
                CuratedImage(
                    id: index,
                    mediaKey: key,
                    filePath: "/preview\(index).jpg",
                    status: .approved,
                    reportWeight: 0,
                    perceptualHash: nil,
                    clusteredWith: nil,
                    difficultyTier: index <= 2 ? .hard : index <= 4 ? .medium : .easy,
                    difficultyRank: nil,
                    moderatorStatus: nil,
                    moderatorAt: nil,
                    disputesDismissedCount: 0,
                    voteAverage: Double(index),
                    voteCount: index * 3,
                    width: 1280,
                    height: 720,
                    aspectRatio: 1.777
                )
            },
            spareFrames: [],
            position: nil,
            playlistTotal: nil
        )
    }

    func fetchCuratedCount(mediaType: MediaType, filters: MediaFilters, excludeWatched: Bool) async throws -> Int {
        87
    }
}

extension MediaItem {
    static func preview(_ id: Int, _ title: String, mediaType: MediaType = .movie) -> MediaItem {
        MediaItem(id: id, mediaType: mediaType, title: title, originalTitle: title, releaseDate: "2024-01-01", overview: nil)
    }
}

enum PreviewSuggestions {
    static let oneLine: [MediaItem] = [
        .preview(1, "Up"),
        .preview(2, "Her"),
        .preview(3, "It"),
        .preview(4, "Inception"),
        .preview(5, "Coco")
    ]

    static let twoLine: [MediaItem] = [
        .preview(1, "The Lord of the Rings: The Fellowship of the Ring"),
        .preview(2, "Star Wars: Episode V — The Empire Strikes Back"),
        .preview(3, "Pirates of the Caribbean: The Curse of the Black Pearl"),
        .preview(4, "Harry Potter and the Prisoner of Azkaban")
    ]

    static let threeLine: [MediaItem] = [
        .preview(1, "Everything Everywhere All at Once: An Absurdist Multiverse Adventure About Taxes and Family"),
        .preview(2, "The Lord of the Rings: The Return of the King — Extended Special Edition Director's Cut")
    ]

    static let mixed: [MediaItem] = [
        .preview(1, "Up"),
        .preview(2, "The Lord of the Rings: The Fellowship of the Ring"),
        .preview(3, "Inception"),
        .preview(4, "Star Wars: Episode V — The Empire Strikes Back"),
        .preview(5, "Her"),
        .preview(6, "Everything Everywhere All at Once: An Absurdist Multiverse Adventure")
    ]

    static let few: [MediaItem] = [
        .preview(1, "Up"),
        .preview(2, "Her")
    ]
}

struct PreviewAuthService: BackendAuthServiceProtocol {
    var user: BackendUser = .preview

    @discardableResult
    func ensureSession() async throws -> BackendUser { user }

    func isSignedIn() async -> Bool { true }

    func currentUser() async -> BackendUser? { user }

    func refreshCurrentUser() async throws -> BackendUser { user }

    @discardableResult
    func signInAnonymously() async throws -> BackendUser { user }

    func signInWithApple(identityToken: String, nonce: String?, displayName: String?) async throws -> BackendUser { user }

    func linkApple(identityToken: String, nonce: String?, displayName: String?) async throws -> BackendUser { user }

    func signOut() async {}

    func forgetAccount() async {}
}

extension BackendUser {
    static let preview = BackendUser(
        uid: "preview",
        role: .admin,
        displayName: nil,
        isAnonymous: true,
        reportMultiplier: 1,
        dailyStreak: 3,
        longestStreak: 7,
        lastDailyCompletedDate: nil,
        bonusAttemptsAvailable: 0,
        attemptsUsedToday: 2,
        lastAttemptResetDate: nil
    )
}
#endif

