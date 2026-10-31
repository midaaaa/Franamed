//
//  PvPProfileEditor.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPProfileEditor: View {
    let profile: PvPProfile
    let isSaving: Bool
    let onSave: (PvPProfileUpdate) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var rolls = 0
    @FocusState private var isNameFocused: Bool

    private static let iconSize: CGFloat = 48
    private static let swatchSize: CGFloat = 34

    init(profile: PvPProfile, isSaving: Bool, onSave: @escaping (PvPProfileUpdate) async -> Bool) {
        self.profile = profile
        self.isSaving = isSaving
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _icon = State(initialValue: profile.icon)
        _color = State(initialValue: profile.color)
    }

    private var check: PvPProfileRules.NameCheck { PvPProfileRules.check(name: name) }

    private var hasChanges: Bool {
        name != profile.name || icon != profile.icon || color != profile.color
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        PvPAvatarView(avatar: PvPAvatar(icon: icon, color: color), size: 44)
                        TextField("Ник", text: $name)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isNameFocused)
                        Button {
                            rolls += 1
                            Task { await reroll() }
                        } label: {
                            Text("🎲")
                                .font(.system(size: 26))
                                .rotationEffect(.degrees(Double(rolls) * 90))
                                .animation(.snappy, value: rolls)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                    if profile.customName {
                        Button("Вернуть сгенерированный ник") {
                            Task { await save(PvPProfileUpdate(generatedName: true), closes: false) }
                        }
                        .disabled(isSaving)
                    }
                } header: {
                    Text("Ник")
                } footer: {
                    Text(PvPProfileRules.hint(for: check) ?? "Латиница, цифры и _, от 3 до 16 символов. 🎲 — случайный ник")
                        .foregroundStyle(check == .valid ? Color.secondary : PvPStyle.miss)
                }

                Section("Иконка") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(PvPProfileRules.icons, id: \.self) { option in
                            Button {
                                icon = option
                                Haptics.shared.play(.menuSelect)
                            } label: {
                                PvPAvatarView(avatar: PvPAvatar(icon: option, color: color), size: Self.iconSize, isDimmed: option != icon)
                                    .overlay {
                                        if option == icon { Circle().strokeBorder(.white, lineWidth: 2) }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Цвет") {
                    HStack(spacing: 0) {
                        ForEach(PvPProfileRules.colors, id: \.self) { option in
                            Button {
                                color = option
                                Haptics.shared.play(.menuSelect)
                            } label: {
                                Circle()
                                    .fill(PvPAvatarStyle.color(option).gradient)
                                    .frame(width: Self.swatchSize, height: Self.swatchSize)
                                    .padding(3)
                                    .overlay {
                                        if option == color { Circle().strokeBorder(.white, lineWidth: 2) }
                                    }
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Готово") {
                            Task { await save(changes, closes: true) }
                        }
                        .disabled(!hasChanges || check != .valid)
                    }
                }
            }
            .onChange(of: profile) { _, updated in
                name = updated.name
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var changes: PvPProfileUpdate {
        PvPProfileUpdate(name: name == profile.name ? nil : name,
                         icon: icon == profile.icon ? nil : icon,
                         color: color == profile.color ? nil : color)
    }

    private func reroll() async {
        isNameFocused = false
        await save(PvPProfileUpdate(reroll: true), closes: false)
    }

    private func save(_ update: PvPProfileUpdate, closes: Bool) async {
        let saved = await onSave(update)
        if saved, closes { dismiss() }
    }
}

#if DEBUG
private struct PvPProfileEditorPreview: View {
    @State var profile: PvPProfile

    var body: some View {
        Color.black
            .sheet(isPresented: .constant(true)) {
                PvPProfileEditor(profile: profile, isSaving: false) { update in
                    guard let updated = try? await PvPPreviewService().updateProfile(update) else { return false }
                    profile = updated
                    return true
                }
            }
    }
}

#Preview("Профиль") {
    PvPProfileEditorPreview(profile: PvPProfile(uid: "you", name: "NoirGaffer", customName: false, alias: "HiddenNoir", icon: "popcorn", color: "red"))
        .preferredColorScheme(.dark)
}

#Preview("Свой ник") {
    PvPProfileEditorPreview(profile: PvPProfile(uid: "you", name: "dima_42", customName: true, alias: "HiddenNoir", icon: "masks", color: "teal"))
        .preferredColorScheme(.dark)
}

#Preview("Сохраняется") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            PvPProfileEditor(profile: PvPProfile(uid: "you", name: "NoirGaffer", customName: false, alias: "HiddenNoir", icon: "star", color: "yellow"),
                             isSaving: true) { _ in true }
        }
        .preferredColorScheme(.dark)
}
#endif
