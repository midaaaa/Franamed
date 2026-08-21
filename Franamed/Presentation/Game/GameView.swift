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
    @State private var selectedMode: MediaType = .movie
    @State private var filtersByMode: [MediaType: MediaFilters] = [:]
    @State private var frameCount: Int = 6

    @State private var isShowingResetConfirmation = false

    private func filters(for mediaType: MediaType) -> MediaFilters {
        filtersByMode[mediaType] ?? MediaFilters()
    }

    private func resetWatchedMovies() {
        do {
            try modelContext.delete(model: WatchedMovieCache.self)
        } catch {
        }
    }

    var body: some View {
        NavigationStack(path: $coordinator.gamePath) {
            TabView(selection: $selectedMode) {
                ForEach(MediaType.allCases) { mode in
                    GameModeList(
                        selectedMode: $selectedMode,
                        onStartRound: { coordinator.showRound(mediaType: mode) },
                        onOpenFilters: {
                            selectedMode = mode
                            isShowingFilters = true
                        }
                    )
                    .tag(mode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(selectedMode.displayName)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .round(let mediaType):
                    RoundView(
                        mediaFacade: AppFactory.makeMediaFacade(),
                        modelContext: modelContext,
                        mediaType: mediaType,
                        filters: filters(for: mediaType),
                        frameCount: frameCount
                    )
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
                        Text("Удалить всю историю просмотренных фильмов и сериалов? Это нельзя отменить.")
                            .foregroundStyle(.secondary)
                        Button("Подтвердить удаление", role: .destructive) {
                            resetWatchedMovies()
                            isShowingResetConfirmation = false
                        }
                        Button("Отмена") {
                            isShowingResetConfirmation = false
                        }
                    } else {
                        Button("Сбросить историю просмотров", role: .destructive) {
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
                    mediaFacade: AppFactory.makeMediaFacade(),
                    mediaType: selectedMode,
                    filters: filters(for: selectedMode),
                    frameCount: frameCount
                ) { newFilters, newFrameCount in
                    filtersByMode[selectedMode] = newFilters
                    frameCount = newFrameCount
                }
            }
        }
    }
}

private struct GameModeList: View {
    @Binding var selectedMode: MediaType
    let onStartRound: () -> Void
    let onOpenFilters: () -> Void

    var body: some View {
        List {
            Picker("Режим", selection: $selectedMode) {
                ForEach(MediaType.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .padding(.horizontal)
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)

            Button("Start Round", action: onStartRound)

            Button(action: onOpenFilters) {
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
    }
}

#Preview {
    GameView(coordinator: AppCoordinator())
        .modelContainer(for: [RoundRecord.self, WatchedMovieCache.self], inMemory: true)
}
