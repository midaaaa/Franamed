//
//  AppCoordinator.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI
import Combine

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var gamePath = NavigationPath()
    @Published var presentedRound: MediaType?
    @Published var presentedPvP: MediaType?
    @Published var pendingPvPCode: String?

    func showRound(mediaType: MediaType) {
        presentedRound = mediaType
    }

    func dismissRound() {
        presentedRound = nil
    }

    func showPvP(mediaType: MediaType) {
        presentedPvP = mediaType
    }

    func openPvP(code: String) {
        presentedRound = nil
        pendingPvPCode = code
        if presentedPvP == nil { presentedPvP = .movie }
    }

    func dismissPvP() {
        presentedPvP = nil
        pendingPvPCode = nil
    }
}
