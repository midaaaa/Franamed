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
    @State private var isShowingFilters = false
    @State private var filters = MovieFilters()
    @State private var frameCount: Int = 6

    var body: some View {
        NavigationStack(path: $coordinator.gamePath) {
            List {
                Button("Start Round") {
                    coordinator.showRound()
                }

                Button {
                    isShowingFilters = true
                } label: {
                    HStack {
                        Text("Фильтры")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .round:
                    RoundView(movieFacade: AppFactory.makeMovieFacade(), filters: filters, frameCount: frameCount)
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
            .sheet(isPresented: $isShowingFilters) {
                RoundFiltersView(
                    movieFacade: AppFactory.makeMovieFacade(),
                    filters: filters,
                    frameCount: frameCount
                ) { newFilters, newFrameCount in
                    filters = newFilters
                    frameCount = newFrameCount
                }
            }
        }
    }
}

#Preview {
    GameView(coordinator: AppCoordinator())
}
