//
//  WatchedSource.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum WatchedSource: String, Codable, Sendable, CaseIterable {
    case play
    case kinopoisk
    case imdb
    case letterboxd
}
