//
//  PvPImageLinks.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

enum PvPImageLinks {
    static let base = BackendConfiguration.default.imageBaseURL
    static let framePath = "/t/p/w1280"

    static func frame(_ path: String) -> URL? {
        URL(string: base + framePath + path)
    }

    static func poster(_ path: String?) -> URL? {
        path.flatMap { URL(string: base + TMDBImageSize.largePath + $0) }
    }

    static func frames(_ frames: [PvPFrame]) -> [URL] {
        frames.compactMap { frame($0.path) }
    }
}
