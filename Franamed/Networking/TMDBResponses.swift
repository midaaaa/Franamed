//
//  TMDBResponses.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import Foundation

struct MediaListResponse {
    let results: [MediaItem]
    let totalPages: Int
    let totalResults: Int
}

struct MovieListResponse: Decodable {
    let results: [MovieDTO]
    let totalPages: Int
    let totalResults: Int
}

struct TVListResponse: Decodable {
    let results: [TVDTO]
    let totalPages: Int
    let totalResults: Int
}

struct MovieDTO: Decodable {
    let id: Int
    let title: String
    let originalTitle: String
    let releaseDate: String?
    let overview: String?

    func asMediaItem() -> MediaItem {
        MediaItem(id: id, mediaType: .movie, title: title, originalTitle: originalTitle, releaseDate: releaseDate, overview: overview)
    }
}

struct TVDTO: Decodable {
    let id: Int
    let name: String
    let originalName: String
    let firstAirDate: String?
    let overview: String?

    func asMediaItem() -> MediaItem {
        MediaItem(id: id, mediaType: .tv, title: name, originalTitle: originalName, releaseDate: firstAirDate, overview: overview)
    }
}

struct BackdropsResponse: Decodable {
    let backdrops: [TMDBBackdropDTO]
}

struct TMDBBackdropDTO: Decodable {
    let filePath: String
    let iso6391: String?
}

struct GenresResponse: Decodable {
    let genres: [Genre]
}
