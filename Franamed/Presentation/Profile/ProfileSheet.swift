//
//  ProfileSheet.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI

struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @AppStorage(DebugSettings.screenProtectionKey) private var isScreenProtected = true
    @AppStorage(DebugSettings.resultStubPlacementKey) private var stubPlacement = ResultStubPlacement.behindForm
    @AppStorage(DebugSettings.phoneAimKey) private var phoneAim = Double(HallPhone.Settings().aim)
    @AppStorage(DebugSettings.phoneWidthKey) private var phoneWidth = Double(HallPhone.Settings().width)
    @AppStorage(DebugSettings.phoneGridKey) private var showsPhoneGrid = false
    @AppStorage(DebugSettings.phoneWideKey) private var isPhoneWide = false

    @EnvironmentObject private var session: SessionStore
    let mediaFacade: MediaFacadeProtocol

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
                    if session.canModerate {
                        Section {
                            Toggle("Не учитывать мою игру", isOn: Binding(
                                get: { user.statsExcluded },
                                set: { excluded in Task { await session.setStatsExcluded(excluded) } }
                            ))
                        } footer: {
                            Text("Пока включено, твои раунды не попадают в общую статистику тайтлов и ежедневки.")
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

                Section("Телефон в зале") {
                    LabeledContent("Поворот к краям", value: phoneAim.formatted(.percent.precision(.fractionLength(0))))
                    Slider(value: $phoneAim, in: 0...1, step: 0.05)
                    LabeledContent("Размер в руке", value: phoneWidth.formatted(.percent.precision(.fractionLength(0))))
                    Slider(value: $phoneWidth, in: 0.4...1, step: 0.05)
                    Toggle("Сетка 3×3", isOn: $showsPhoneGrid)
                    Toggle("Кадр камеры 16:9", isOn: $isPhoneWide)
                }
                #endif

                Section {
                    Button("Сбросить сыгранное", role: .destructive) {
                        isConfirmingReset = true
                    }
                    .confirmationDialog(
                        "Сбросить сыгранное в курируемом рандоме?",
                        isPresented: $isConfirmingReset,
                        titleVisibility: .visible
                    ) {
                        Button("Сбросить", role: .destructive) {
                            Task { try? await mediaFacade.resetPlayedTitles() }
                        }
                    } message: {
                        Text("Все тайтлы снова станут новыми. Это нельзя отменить.")
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
    ProfileSheet(mediaFacade: PreviewMediaFacade())
        .environmentObject(SessionStore(auth: PreviewAuthService()))
}
