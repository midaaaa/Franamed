//
//  FranamedApp.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 11.08.2026.
//

import SwiftUI

@main
struct FranamedApp: App {
    let mediaFacade = AppFactory.makeMediaFacade()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 300 << 20)
    }

    var body: some Scene {
        WindowGroup {
            RootView(mediaFacade: mediaFacade)
        }
    }
}
