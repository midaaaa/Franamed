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

    static func makeFirestoreService() -> FirestoreServiceProtocol {
        return StubFirestoreService()
    }

    static func makeMediaFacade() -> MediaFacadeProtocol {
        let tmdbClient = makeTMDBClient()
        let firestoreService = makeFirestoreService()

        return MediaFacade(tmdbClient: tmdbClient, firestoreService: firestoreService)
    }
}
