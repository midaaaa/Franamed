//
//  PvPJSONResultStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

actor PvPJSONResultStore: PvPResultStore {
    private let url: URL
    private let limit: Int
    private var cached: [PvPMatchResult]?

    init(url: URL, limit: Int = 50) {
        self.url = url
        self.limit = limit
    }

    static func standard() -> PvPJSONResultStore {
        PvPJSONResultStore(url: URL.applicationSupportDirectory.appendingPathComponent("PvP/results.json"))
    }

    func save(_ result: PvPMatchResult) {
        var results = load().filter { $0.id != result.id }
        results.insert(result, at: 0)
        write(Array(results.prefix(limit)))
    }

    func results() -> [PvPMatchResult] {
        load()
    }

    func remove(id: String) {
        write(load().filter { $0.id != id })
    }

    private func load() -> [PvPMatchResult] {
        if let cached { return cached }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([PvPMatchResult].self, from: $0) } ?? []
        cached = loaded
        return loaded
    }

    private func write(_ results: [PvPMatchResult]) {
        cached = results
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(results) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
