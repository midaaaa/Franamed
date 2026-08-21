//
//  FranamedApp.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 11.08.2026.
//

import SwiftUI
import SwiftData

@main
struct FranamedApp: App {
    let container: ModelContainer = {
        let schema = Schema([RoundRecord.self, WatchedMovieCache.self])
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Не удалось создать ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }
}
