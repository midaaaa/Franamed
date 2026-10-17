//
//  PlaylistDetail+Presentation.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import Foundation

enum PlaylistCompletion {
    case inProgress
    case passed
    case perfect
}

enum PlaylistEntryDisplay: Equatable {
    case guessed(frame: Int)
    case missed
    case next
    case upcoming
}

extension PlaylistDetail {
    static let frameCount = 6

    var playableItems: [PlaylistEntry] { items.filter(\.isPlayable) }
    var availableCount: Int { playableItems.count }
    var answeredCount: Int { items.filter { $0.state == .completed }.count }
    var correctCount: Int { items.filter { $0.wasCorrect == true }.count }

    var isFinished: Bool {
        answeredCount > 0 && !playableItems.contains { $0.state != .completed }
    }

    var completion: PlaylistCompletion {
        guard isFinished else { return .inProgress }
        return correctCount >= availableCount ? .perfect : .passed
    }

    func display(of entry: PlaylistEntry) -> PlaylistEntryDisplay {
        if entry.state == .completed {
            return entry.wasCorrect == true ? .guessed(frame: entry.attemptsUsed) : .missed
        }
        let next = playableItems.first { $0.state != .completed }
        return entry.key == next?.key ? .next : .upcoming
    }

    var coverURL: URL? { coverImageURL.flatMap(URL.init(string:)) }
    var largeCoverURL: URL? { coverImageURL.flatMap(TMDBImageSize.large) }

    func folderPosters(count: Int) -> [URL?] {
        if let folderPosters, !folderPosters.isEmpty {
            return folderPosters.prefix(count).map { URL(string: $0) }
        }
        let sides = items
            .filter { $0.posterURL != nil && $0.posterURL != coverImageURL }
            .sorted { PlaylistSeed.hash(id + $0.key) < PlaylistSeed.hash(id + $1.key) }
            .prefix(max(0, count - 1))
            .map(\.posterImageURL)
        return [coverURL] + sides
    }
}

extension PlaylistEntry {
    var isPlayable: Bool {
        playable != false && approvedImages >= PlaylistDetail.frameCount
    }

    var posterImageURL: URL? { posterURL.flatMap(URL.init(string:)) }
    var largePosterImageURL: URL? { posterURL.flatMap(TMDBImageSize.large) }
}

enum TMDBImageSize {
    static let smallPath = "/t/p/w342"
    static let largePath = "/t/p/w780"

    static func large(_ url: String) -> URL? {
        URL(string: url.replacingOccurrences(of: smallPath, with: largePath))
    }

    static func small(of url: URL) -> URL? {
        URL(string: url.absoluteString.replacingOccurrences(of: largePath, with: smallPath))
    }
}

enum PlaylistSeed {
    static func hash(_ seed: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return hash
    }

    static func unit(_ seed: String) -> Double {
        Double(hash(seed) % 1_000) / 1_000
    }
}
