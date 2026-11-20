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
    @Published var pendingPvPCode: String?

    func showRound(mediaType: MediaType) {
        presentedRound = mediaType
    }

    func dismissRound() {
        presentedRound = nil
    }

    /// A room link opens the PvP ticket on the main screen and joins the room.
    func openPvP(code: String) {
        presentedRound = nil
        pendingPvPCode = code
    }
}
