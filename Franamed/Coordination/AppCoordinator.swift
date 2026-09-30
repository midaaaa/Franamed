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

    func showRound(mediaType: MediaType) {
        presentedRound = mediaType
    }

    func dismissRound() {
        presentedRound = nil
    }
}
