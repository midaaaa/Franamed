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
        TabView {
            GameView(coordinator: coordinator)
                .tabItem { Label("Game", systemImage: "gamecontroller") }

            CurationView(coordinator: coordinator)
                .tabItem { Label("Curation", systemImage: "checkmark.seal") }
        }
    }
}

#Preview {
    RootView()
}
