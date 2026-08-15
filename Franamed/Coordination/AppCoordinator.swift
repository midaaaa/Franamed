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
    @Published var curationPath = NavigationPath()

    func showRound() {
        gamePath.append(Route.round)
    }

    func showCurationQueue() {
        curationPath.append(CurationRoute.queue)
    }
}
