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
            .providesWindowGeometry()
            .background(WindowSizeRestrictions(minimumSize: Self.minimumWindowSize))
            .task { await session.start() }
            .onOpenURL { url in
                guard let link = PvPRoomLink(url: url) else { return }
                coordinator.openPvP(code: link.code)
            }
    }

    private static let minimumWindowSize = CGSize(width: 390, height: 640)
}

#Preview {
    RootView(session: SessionStore(auth: PreviewAuthService()), mediaFacade: PreviewMediaFacade())
}
