//
//  TicketTearSeeds.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 28.10.2026.
//

import Foundation

struct TicketTearSeeds {
    private var seeds: [String: UInt64]
    private let defaults: UserDefaults

    private static let storageKey = "ticketTearSeeds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        seeds = stored.compactMapValues(UInt64.init)

        let missing = TicketGameMode.allCases.flatMap { mode in
            MediaType.allCases.map { Self.key(mode: mode, mediaType: $0) }
        }.filter { seeds[$0] == nil }
        guard !missing.isEmpty else { return }
        for key in missing { seeds[key] = FlipTear.randomSeed() }
        save()
    }

    func seed(mode: TicketGameMode, mediaType: MediaType) -> UInt64 {
        seeds[Self.key(mode: mode, mediaType: mediaType)] ?? 1
    }

    mutating func renew(mode: TicketGameMode, mediaType: MediaType) {
        seeds[Self.key(mode: mode, mediaType: mediaType)] = FlipTear.randomSeed()
        save()
    }

    private func save() {
        defaults.set(seeds.mapValues(String.init), forKey: Self.storageKey)
    }

    private static func key(mode: TicketGameMode, mediaType: MediaType) -> String {
        "\(mode.rawValue)_\(mediaType.rawValue)"
    }
}
