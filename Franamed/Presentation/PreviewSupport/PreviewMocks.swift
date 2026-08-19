//
//  PreviewMocks.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

#if DEBUG
struct PreviewMovieFacade: MovieFacadeProtocol {
    func searchMovies(query: String, language: String) async throws -> [Movie] {[
        Movie(id: 1, title: "Movie 1", releaseDate: "2025-04-05", overview: "Preview overview 1", originalTitle: "Movie 1"),
        Movie(id: 2, title: "Movie 2", releaseDate: "2026-04-05", overview: "Preview overview 2", originalTitle: "Movie 2")
    ]}

    func fetchRandomMovieAndBackdrops(filters: MovieFilters, frameCount: Int) async throws -> MovieWithBackdrops {
        MovieWithBackdrops(
            movie: Movie(id: 1, title: "Preview Movie", releaseDate: "2024-01-01", overview: "Preview overview", originalTitle: "Preview Movie"),
            backdrops: (1...6).map { Backdrop(filePath: "https://picsum.photos/seed/backdrop\($0)/1280/720") }
        )
    }

    func fetchGenres() async throws -> [Genre] {
        [
            Genre(id: 1, name: "Драма"),
            Genre(id: 2, name: "Комедия"),
            Genre(id: 3, name: "Фантастика")
        ]
    }

    func fetchResultsCount(filters: MovieFilters) async throws -> Int {
        124
    }
}

extension Movie {
    static func preview(_ id: Int, _ title: String) -> Movie {
        Movie(id: id, title: title, releaseDate: "2024-01-01", overview: nil, originalTitle: title)
    }
}

enum PreviewSuggestions {
    static let oneLine: [Movie] = [
        .preview(1, "Up"),
        .preview(2, "Her"),
        .preview(3, "It"),
        .preview(4, "Inception"),
        .preview(5, "Coco")
    ]

    static let twoLine: [Movie] = [
        .preview(1, "The Lord of the Rings: The Fellowship of the Ring"),
        .preview(2, "Star Wars: Episode V — The Empire Strikes Back"),
        .preview(3, "Pirates of the Caribbean: The Curse of the Black Pearl"),
        .preview(4, "Harry Potter and the Prisoner of Azkaban")
    ]

    static let threeLine: [Movie] = [
        .preview(1, "Everything Everywhere All at Once: An Absurdist Multiverse Adventure About Taxes and Family"),
        .preview(2, "The Lord of the Rings: The Return of the King — Extended Special Edition Director's Cut")
    ]

    static let mixed: [Movie] = [
        .preview(1, "Up"),
        .preview(2, "The Lord of the Rings: The Fellowship of the Ring"),
        .preview(3, "Inception"),
        .preview(4, "Star Wars: Episode V — The Empire Strikes Back"),
        .preview(5, "Her"),
        .preview(6, "Everything Everywhere All at Once: An Absurdist Multiverse Adventure")
    ]

    static let few: [Movie] = [
        .preview(1, "Up"),
        .preview(2, "Her")
    ]
}
#endif
