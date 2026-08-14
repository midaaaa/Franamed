//
//  RootView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI

struct RootView: View {
    @StateObject private var coordinator = AppCoordinator()

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            Button("Start Round") {
                coordinator.showRound()
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .round:
                    Text("Round placeholder")
                }
            }
        }
    }
}
