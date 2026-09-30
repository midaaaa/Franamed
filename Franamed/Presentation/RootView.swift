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

    init(session: SessionStore = SessionStore()) {
        _session = StateObject(wrappedValue: session)
    }

    private static let isBackendEnabled = false

    var body: some View {
        Group {
            if Self.isBackendEnabled {
                switch session.state {
                case .loading:
                    SessionLoadingView()

                case .signedOut:
                    SignInView(onPlay: { await session.signInAnonymously() })

                case let .failed(message):
                    SessionFailureView(message: message, onRetry: { await session.start() })

                case .signedIn:
                    game
                }
            } else {
                game
            }
        }
        .task {
            guard Self.isBackendEnabled else { return }
            await session.start()
        }
    }

    private var game: some View {
        TicketView(coordinator: coordinator)
            .modelContext(modelContext)
            .environmentObject(session)
    }
}

#Preview {
    RootView(session: SessionStore(auth: PreviewAuthService()))
        .modelContainer(for: [RoundRecord.self, WatchedRecord.self], inMemory: true)
}
