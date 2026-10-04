//
//  TicketViewModel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 04.10.2026.
//

import Foundation
import Combine

@MainActor
final class TicketViewModel: ObservableObject {
    let mediaFacade: MediaFacadeProtocol
    @Published private(set) var mediaType: MediaType = .movie
    @Published private(set) var mode: TicketGameMode = .random
    @Published private(set) var setupByMode: [MediaType: RoundSetup] = [:]
    @Published private(set) var genreNamesByType: [MediaType: [Int: String]] = [:]

    init(mediaFacade: MediaFacadeProtocol) {
        self.mediaFacade = mediaFacade
    }

    private static let posterPaths: [MediaType: String] = [
        .movie: "bcaBRNNuxC2N4DsffAilIueQOVc.jpg",
        .tv: "7TOPrmrJ8qO5cKJa7r6WSnjim54.jpg",
    ]

    var card: TicketCard {
        TicketCard(mediaType: mediaType, posterPath: Self.posterPaths[mediaType], mode: mode)
    }

    func setup(for mediaType: MediaType) -> RoundSetup {
        setupByMode[mediaType] ?? RoundSetup()
    }

    func genreNames(for mediaType: MediaType) -> [String] {
        guard let ids = setup(for: mediaType).filters.genres, !ids.isEmpty,
              let lookup = genreNamesByType[mediaType] else { return [] }
        return ids.compactMap { lookup[$0] }
    }

    func loadGenreNames() async {
        for mediaType in MediaType.allCases where genreNamesByType[mediaType] == nil {
            let genres = (try? await self.mediaFacade.fetchGenres(mediaType: mediaType)) ?? []
            genreNamesByType[mediaType] = Dictionary(
                genres.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    func select(mediaType: MediaType) {
        self.mediaType = mediaType
    }

    func select(mode: TicketGameMode) {
        self.mode = mode
    }

    func saveSetup(_ roundSetup: RoundSetup, for mediaType: MediaType) {
        setupByMode[mediaType] = roundSetup
    }
}
