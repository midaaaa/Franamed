//
//  PlaylistEntry+Ticket.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import Foundation

extension PlaylistEntryDisplay {
    var isPlayed: Bool { outcome != nil }

    var outcome: RoundOutcome? {
        switch self {
        case .guessed: .correct
        case .missed: .incorrect
        case .next, .upcoming: nil
        }
    }
}

struct PlaylistMediaRef: Hashable {
    let mediaType: MediaType
    let id: Int

    init?(key: String) {
        guard let separator = key.lastIndex(of: "_"),
              let mediaType = MediaType(rawValue: String(key[..<separator])),
              let id = Int(key[key.index(after: separator)...]) else { return nil }
        self.mediaType = mediaType
        self.id = id
    }
}

extension PlaylistEntry {
    var mediaType: MediaType {
        PlaylistMediaRef(key: key)?.mediaType ?? .movie
    }

    var stubTearSeed: UInt64 { tearSeed ?? PlaylistSeed.hash(key) }

    func stubCut(_ display: PlaylistEntryDisplay) -> PlaylistStubCut {
        switch display {
        case .guessed: .detached
        case .missed: .ripped(seed: stubTearSeed)
        case .next, .upcoming: .attached
        }
    }

    func progress(_ display: PlaylistEntryDisplay) -> ResultStubProgress {
        guard let outcome = display.outcome else { return .unplayed(frameCount: PlaylistDetail.frameCount) }
        return .finished(frameCount: PlaylistDetail.frameCount, attemptsMade: attemptsUsed, outcome: outcome)
    }

    func stubContent(display: PlaylistEntryDisplay, details: MediaDetails?) -> ResultStubContent {
        let item = MediaItem(id: PlaylistMediaRef(key: key)?.id ?? 0, mediaType: mediaType, title: title,
                             originalTitle: title, releaseDate: releaseYear.map(String.init), overview: nil)
        let date = playedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
        return ResultStubContent(item: item, mediaType: mediaType, details: details, outcome: display.outcome,
                                 attemptsUsed: max(attemptsUsed, 1), playedAt: date, progress: progress(display))
    }
}
