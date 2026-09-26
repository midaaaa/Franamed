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
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @AppStorage(DebugSettings.overlayKey) private var showsDebugOverlay = true
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true

    @EnvironmentObject private var session: SessionStore

    @State private var isConfirming = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Вибрация", isOn: $hapticsEnabled)
                    Toggle("Вырезы по краю билета", isOn: $hasScallops)
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
                            try? modelContext.delete(model: WatchedRecord.self)
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
                    Toggle("Прятать кадр от съёмки", isOn: $isScreenProtected)
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
        .modelContainer(for: [RoundRecord.self, WatchedRecord.self], inMemory: true)
}
