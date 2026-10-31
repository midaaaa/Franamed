//
//  PvPAnswerSearch.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Combine
import Foundation

@MainActor
final class PvPAnswerSearch: ObservableObject {
    @Published var text = ""
    @Published private(set) var results: [MediaItem] = []
    @Published private(set) var hasSearched = false

    private var selected: MediaItem?
    private var token = 0
    private let mediaFacade: MediaFacadeProtocol

    private static let cyrillicRange: ClosedRange<Unicode.Scalar> = "\u{0400}"..."\u{04FF}"

    init(mediaFacade: MediaFacadeProtocol) {
        self.mediaFacade = mediaFacade
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func select(_ item: MediaItem) {
        selected = item
        text = item.title
    }

    func pick() -> MediaItem? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected, selected.title == typed { return selected }
        return results.first { item in
            [item.title, item.originalTitle].contains { $0.caseInsensitiveCompare(typed) == .orderedSame }
        }
    }

    func reset() {
        token &+= 1
        text = ""
        selected = nil
        results = []
        hasSearched = false
    }

    func search(mediaType: MediaType) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = token
        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            return
        }
        guard current == token else { return }
        guard !query.isEmpty else {
            results = []
            hasSearched = false
            return
        }
        let isCyrillic = query.unicodeScalars.contains { Self.cyrillicRange.contains($0) }
        let found = (try? await mediaFacade.searchMedia(mediaType: mediaType, query: query, language: isCyrillic ? "ru-RU" : "en-US")) ?? []
        guard current == token else { return }
        var seen = Set<String>()
        results = found.filter { seen.insert($0.title).inserted }
        hasSearched = true
    }
}
