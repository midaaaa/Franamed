//
//  AppFactory.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

enum AppFactory {
    static func makeTMDBClient() -> TMDBClientProtocol {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String,
              !apiKey.isEmpty else {
            fatalError("TMDBAPIKey не найден в Info.plist — проверь Config/Secrets.xcconfig")
        }
        return TMDBClient(apiKey: apiKey)
    }

    private static let sharedBackend = Backend()

    static func makeBackend() -> Backend {
        sharedBackend
    }

    static func makeMediaFacade() -> MediaFacadeProtocol {
        MediaFacade(tmdbClient: makeTMDBClient(), backend: makeBackend())
    }
}
