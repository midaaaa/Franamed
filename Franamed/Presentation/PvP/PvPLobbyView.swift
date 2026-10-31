//
//  PvPLobbyView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI
import UIKit

struct PvPLobbyView: View {
    let screen: PvPLobbyScreen
    let onAction: (PvPAction.Kind) -> Void
    let onChange: (PvPSettingRow.Field, Int) -> Void
    let onPlayer: (PvPPlayerAction, String) -> Void

    var body: some View {
        PvPPage {
            PvPCodeCard(code: screen.code, invite: screen.invite)
            players
            settings
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var players: some View {
        VStack(spacing: 8) {
            PvPKicker(text: "Игроки · \(screen.seats)")
            PvPCard(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(screen.players.enumerated()), id: \.element.id) { index, row in
                        PvPPlayerRowView(row: row, onAction: onPlayer)
                        if index < screen.players.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
            .animation(.snappy, value: screen.players)
        }
    }

    private var settings: some View {
        VStack(spacing: 8) {
            PvPKicker(text: "Настройки")
            PvPCard {
                VStack(spacing: 14) {
                    ForEach(screen.settings) { row in
                        PvPSettingRowView(row: row) { onChange(row.field, $0) }
                    }
                }
            }
            Text(screen.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let hint = screen.hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            PvPPrimaryButton(title: screen.primary.title, isEnabled: screen.primary.isEnabled) {
                Haptics.shared.play(.menuSelect)
                onAction(screen.primary.kind)
            }
        }
        .frame(maxWidth: PvPStyle.maxWidth)
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.snappy, value: screen.hint)
    }
}

enum PvPPlayerAction {
    case kick
    case hideName
    case toggleHidden
}

// MARK: - Code

struct PvPCodeCard: View {
    let code: String
    let invite: PvPInvite?

    @State private var isCopied = false

    var body: some View {
        PvPCard {
            VStack(alignment: .leading, spacing: 12) {
                PvPKicker(text: "Код комнаты")
                HStack {
                    Text(code)
                        .font(PvPStyle.code)
                        .tracking(6)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = invite?.text ?? code
                        Haptics.shared.play(.menuSelect)
                        isCopied = true
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 17, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                if let invite {
                    ShareLink(item: invite.url, message: Text(invite.text)) {
                        Label("Поделиться приглашением", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .task(id: isCopied) {
            guard isCopied else { return }
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }
}

// MARK: - Player

struct PvPPlayerRowView: View {
    let row: PvPPlayerRow
    let onAction: (PvPPlayerAction, String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            PvPAvatarView(avatar: row.avatar, isDimmed: row.tone == .left || row.tone == .offline)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.body.weight(row.isYou ? .semibold : .regular))
                        .lineLimit(1)
                    if row.isYou {
                        Text("вы")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if row.isHost {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(PvPStyle.win)
                    }
                    if row.isNameHidden {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(row.status)
                    .font(.caption)
                    .foregroundStyle(PvPStyle.tone(row.tone))
            }
            Spacer(minLength: 0)
            if row.hasActions {
                menu
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: PvPStyle.rowHeight)
        .contentShape(.rect)
    }

    private var menu: some View {
        Menu {
            if row.canHideForMe {
                Button(row.isNameHidden ? "Показать ник" : "Скрыть ник у меня",
                       systemImage: row.isNameHidden ? "eye" : "eye.slash") { onAction(.toggleHidden, row.uid) }
            }
            if row.canHideName {
                Button("Скрыть ник у всех", systemImage: "theatermasks") { onAction(.hideName, row.uid) }
            }
            if row.canKick {
                Button("Удалить из комнаты", systemImage: "person.fill.xmark", role: .destructive) { onAction(.kick, row.uid) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Setting

struct PvPSettingRowView: View {
    let row: PvPSettingRow
    let onChange: (Int) -> Void

    var body: some View {
        if row.isEditable {
            VStack(alignment: .leading, spacing: 8) {
                Text(row.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker(row.title, selection: Binding(get: { row.selected }, set: { onChange($0) })) {
                    ForEach(row.options) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.segmented)
            }
        } else {
            LabeledContent(row.title) {
                Text(row.selectedLabel)
                    .monospacedDigit()
            }
        }
    }
}

#if DEBUG
@MainActor
private func lobbyPreview(_ state: PvPMatchState) -> some View {
    Group {
        if let lobby = PvPPreview.lobby(state) {
            NavigationStack {
                PvPLobbyView(screen: lobby, onAction: { _ in }, onChange: { _, _ in }, onPlayer: { _, _ in })
                    .navigationTitle("Комната")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Лобби, хост") { lobbyPreview(PvPMatchFixtures.lobbyHost) }
#Preview("Лобби, гость") { lobbyPreview(PvPMatchFixtures.lobbyGuest) }
#Preview("Лобби дуэли") { lobbyPreview(PvPMatchFixtures.lobbyDuel) }
#Preview("Лобби, один") { lobbyPreview(PvPMatchFixtures.lobbyAlone) }

#Preview("Код без приглашения") {
    PvPCodeCard(code: PvPMatchFixtures.roomCode, invite: nil)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Строки игроков") {
    if let lobby = PvPPreview.lobby(PvPMatchFixtures.lobbyHost) {
        VStack(spacing: 0) {
            ForEach(lobby.players) { PvPPlayerRowView(row: $0) { _, _ in } }
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}

#Preview("Настройки хоста") {
    if let lobby = PvPPreview.lobby(PvPMatchFixtures.lobbyHost) {
        VStack(spacing: 14) {
            ForEach(lobby.settings) { PvPSettingRowView(row: $0) { _ in } }
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}

#Preview("Настройки дуэли") {
    if let lobby = PvPPreview.lobby(PvPMatchFixtures.lobbyDuel) {
        VStack(spacing: 14) {
            ForEach(lobby.settings) { PvPSettingRowView(row: $0) { _ in } }
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
#endif
