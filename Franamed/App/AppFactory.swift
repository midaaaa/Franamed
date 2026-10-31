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

    private static let pvpResults = PvPJSONResultStore.standard()

    static func makePvPService() -> any PvPServiceProtocol {
        BackendPvPService(client: makeBackend().client)
    }

    static func makePvPSession(room: PvPRoomTicket, code: String) -> any PvPSessionProtocol {
        PvPMatchSession(room: room, code: code, reducer: PvPMatchMachine(), preloader: PvPFrameDownloadsPreloader(),
                        resultStore: pvpResults, makeTransport: { PvPSocketTransport() })
    }
}
