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
    @StateObject private var session: SessionStore
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark

    init(session: SessionStore = SessionStore()) {
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                SessionLoadingView()

            case .signedOut:
                SignInView(onPlay: { await session.signInAnonymously() })

            case let .failed(message):
                SessionFailureView(message: message, onRetry: { await session.start() })

            case .signedIn:
                tabs
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { await session.start() }
    }

    private var tabs: some View {
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
        .environmentObject(session)
    }
}

#Preview {
    RootView(session: SessionStore(auth: PreviewAuthService()))
        .modelContainer(for: [RoundRecord.self, WatchedMovieCache.self], inMemory: true)
}
