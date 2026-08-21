//
//  GameView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI
import SwiftData

struct GameView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingProfile = false
    @State private var isShowingFilters = false
    @State private var filters = MovieFilters()
    @State private var frameCount: Int = 6

    @State private var isShowingResetConfirmation = false

    private func resetWatchedMovies() {
        do {
            try modelContext.delete(model: WatchedMovieCache.self)
        } catch {
        }
    }

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
                    RoundView(movieFacade: AppFactory.makeMovieFacade(), modelContext: modelContext, filters: filters, frameCount: frameCount)
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
                List {
                    if isShowingResetConfirmation {
                        Text("Удалить всю историю просмотренных фильмов? Это нельзя отменить.")
                            .foregroundStyle(.secondary)
                        Button("Подтвердить удаление", role: .destructive) {
                            resetWatchedMovies()
                            isShowingResetConfirmation = false
                        }
                        Button("Отмена") {
                            isShowingResetConfirmation = false
                        }
                    } else {
                        Button("Сбросить просмотренные фильмы", role: .destructive) {
                            isShowingResetConfirmation = true
                        }
                    }
                }
                .onDisappear {
                    isShowingResetConfirmation = false
                }
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
        .modelContainer(for: [RoundRecord.self, WatchedMovieCache.self], inMemory: true)
}
