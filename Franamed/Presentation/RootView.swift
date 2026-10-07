//
//  RootView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI

struct RootView: View {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var session: SessionStore
    let mediaFacade: MediaFacadeProtocol

    init(session: SessionStore = SessionStore(), mediaFacade: MediaFacadeProtocol) {
        _session = StateObject(wrappedValue: session)
        self.mediaFacade = mediaFacade
    }

    var body: some View {
        TicketView(coordinator: coordinator, mediaFacade: mediaFacade)
            .environmentObject(session)
            .task { await session.start() }
    }
}

#Preview {
    RootView(session: SessionStore(auth: PreviewAuthService()), mediaFacade: PreviewMediaFacade())
}
