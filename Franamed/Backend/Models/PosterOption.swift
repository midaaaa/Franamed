//
//  PosterOption.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct PosterOption: Codable, Sendable, Identifiable {
    let filePath: String
    let language: String?
    let voteAverage: Double
    let width: Int
    let height: Int

    var id: String { filePath }

    func url(imageBaseURL: String) -> URL? {
        URL(string: "\(imageBaseURL)/t/p/w500\(filePath)")
    }
}
