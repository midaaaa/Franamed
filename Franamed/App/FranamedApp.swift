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

    var body: some Scene {
        WindowGroup {
            RootView(mediaFacade: mediaFacade)
        }
    }
}
