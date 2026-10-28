//
//  PlaylistRoundResume.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 28.10.2026.
//

import Foundation

struct PlaylistRoundResume: Codable {
    let media: MediaItemWithBackdrops
    let attemptsMade: Int
    let frameCount: Int

    var mediaKey: String {
        "\(media.item.mediaType.rawValue)_\(media.item.id)"
    }
}

struct PlaylistRoundResumes {
    private let defaults: UserDefaults

    private static let storageKey = "playlists.resumes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String: PlaylistRoundResume] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PlaylistRoundResume].self, from: data)) ?? [:]
    }

    func save(_ resumes: [String: PlaylistRoundResume]) {
        guard let data = try? JSONEncoder().encode(resumes) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
