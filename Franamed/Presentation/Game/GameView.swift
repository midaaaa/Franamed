//
//  GameView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI

struct GameView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var isShowingProfile = false

    var body: some View {
        NavigationStack(path: $coordinator.gamePath) {
            List {
                Button("Start Round") {
                    coordinator.showRound()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .round:
                    RoundView(movieFacade: AppFactory.makeMovieFacade())
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingProfile) {
                Text("Profile placeholder")
            }
        }
    }
}

#Preview {
    GameView(coordinator: AppCoordinator())
}
