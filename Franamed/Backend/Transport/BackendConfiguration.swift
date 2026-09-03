//
//  BackendConfiguration.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct BackendConfiguration: Sendable {
    let apiBaseURL: String
    let imageBaseURL: String

    static let `default` = BackendConfiguration(
        apiBaseURL: "https://franamed-api.fildima8423.workers.dev",
        imageBaseURL: "https://franamed-tmdb-proxy.fildima8423.workers.dev"
    )
}
