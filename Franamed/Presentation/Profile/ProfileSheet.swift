//
//  ProfileSheet.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI
import SwiftData

struct ProfileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark
    @AppStorage(DebugSettings.overlayKey) private var showsDebugOverlay = true
    @AppStorage(DebugSettings.returnStyleKey) private var returnStyle = TearReturnStyle.curled
    @AppStorage(DebugSettings.returnShrinkKey) private var shrinksOnReturn = false

    @EnvironmentObject private var session: SessionStore

    @State private var isConfirming = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Оформление", selection: $appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Оформление")
                }

                Section {
                    if let user = session.user {
                        LabeledContent("Роль", value: user.role.displayName)
                        LabeledContent("Аккаунт", value: user.isAnonymous ? "Анонимный" : (user.displayName ?? "Связан с Apple ID"))
                        LabeledContent("Серия", value: "\(user.dailyStreak)")
                    }

                    Button("Выйти", role: .destructive) {
                        Task {
                            dismiss()
                            await session.signOut()
                        }
                    }
                } header: {
                    Text("Аккаунт")
                }

                Section {
                    if isConfirming {
                        Text("Удалить всю историю просмотренных фильмов и сериалов? Это нельзя отменить.")
                            .foregroundStyle(.secondary)
                        Button("Подтвердить удаление", role: .destructive) {
                            try? modelContext.delete(model: WatchedMovieCache.self)
                            isConfirming = false
                        }
                        Button("Отмена") {
                            isConfirming = false
                        }
                    } else {
                        Button("Сбросить историю просмотров", role: .destructive) {
                            isConfirming = true
                        }
                    }
                } header: {
                    Text("История")
                }

                #if DEBUG
                Section {
                    Toggle("Отладочный оверлей", isOn: $showsDebugOverlay)
                    Picker("Возврат корешка", selection: $returnStyle) {
                        ForEach(TearReturnStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    Toggle("Ужимать билет", isOn: $shrinksOnReturn)
                } header: {
                    Text("Отладка")
                }
                #endif
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ProfileSheet()
        .environmentObject(SessionStore(auth: PreviewAuthService()))
        .modelContainer(for: [RoundRecord.self, WatchedMovieCache.self], inMemory: true)
}
