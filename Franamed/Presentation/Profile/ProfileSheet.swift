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
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true
    @AppStorage(DebugSettings.resultStubPlacementKey) private var stubPlacement = ResultStubPlacement.behindForm

    @EnvironmentObject private var session: SessionStore

    @State private var isConfirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section("Аккаунт") {
                        LabeledContent("Аккаунт", value: user.isAnonymous ? "Анонимный" : (user.displayName ?? "Apple ID"))
                        if session.canModerate {
                            LabeledContent("Роль", value: user.role.displayName)
                        }
                    }
                }

                Section("Настройки") {
                    Toggle("Вибрация", isOn: $hapticsEnabled)
                }

                #if DEBUG
                Section {
                    Toggle("Прятать кадр от съёмки", isOn: $isScreenProtected)
                    Toggle("Обрезать корешок формой", isOn: Binding(
                        get: { stubPlacement == .clippedByForm },
                        set: { stubPlacement = $0 ? .clippedByForm : .behindForm }
                    ))
                    Toggle("Вырезы по краю билета", isOn: $hasScallops)
                }
                #endif

                Section {
                    Button("Сбросить историю просмотров", role: .destructive) {
                        isConfirmingReset = true
                    }
                    .confirmationDialog(
                        "Удалить всю историю просмотренных фильмов и сериалов?",
                        isPresented: $isConfirmingReset,
                        titleVisibility: .visible
                    ) {
                        Button("Удалить историю", role: .destructive) {
                            try? modelContext.delete(model: WatchedRecord.self)
                        }
                    } message: {
                        Text("Это нельзя отменить.")
                    }
                }
            }
            .navigationTitle("Профиль")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
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
