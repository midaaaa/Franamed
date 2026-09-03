//
//  Backend.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct Backend: Sendable {
    let configuration: BackendConfiguration
    let auth: BackendAuthServiceProtocol
    let catalog: BackendCatalogServiceProtocol
    let round: BackendRoundServiceProtocol
    let curation: BackendCurationServiceProtocol
    let playlists: BackendPlaylistServiceProtocol
    let profile: BackendProfileServiceProtocol
    let admin: BackendAdminServiceProtocol

    init(configuration: BackendConfiguration = .default, session: URLSession = .shared) {
        let client = BackendAPIClient(configuration: configuration, session: session)

        self.configuration = configuration
        self.auth = BackendAuthService(client: client)
        self.catalog = BackendCatalogService(client: client)
        self.round = BackendRoundService(client: client)
        self.curation = BackendCurationService(client: client)
        self.playlists = BackendPlaylistService(client: client)
        self.profile = BackendProfileService(client: client)
        self.admin = BackendAdminService(client: client)
    }
}
