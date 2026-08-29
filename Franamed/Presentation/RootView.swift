//
//  RootView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var coordinator = AppCoordinator()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark

    var body: some View {
        TabView {
            Tab("Game", systemImage: "gamecontroller") {
                TicketView(coordinator: coordinator)
                    .modelContext(modelContext)
            }

            Tab("Curation", systemImage: "checkmark.seal") {
                CurationView(coordinator: coordinator)
                    .modelContext(modelContext)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }
}

#Preview {
    RootView()
}
