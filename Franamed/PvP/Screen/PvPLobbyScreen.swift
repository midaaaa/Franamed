//
//  PvPLobbyScreen.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

// MARK: - Lobby

struct PvPLobbyScreen: Sendable, Equatable {
    let kind: PvPRoomKind
    let code: String
    let invite: PvPInvite?
    let players: [PvPPlayerRow]
    let seats: String
    let settings: [PvPSettingRow]
    let summary: String
    let primary: PvPAction
    let hint: String?
}

struct PvPInvite: Sendable, Equatable {
    let url: URL
    let text: String
}

struct PvPPlayerRow: Sendable, Equatable, Identifiable {
    enum Tone: Sendable, Equatable {
        case ready
        case waiting
        case away
        case offline
        case left
    }

    let uid: String
    let name: String
    let avatar: PvPAvatar
    let isYou: Bool
    let isHost: Bool
    let status: String
    let tone: Tone
    let isNameHidden: Bool
    let canKick: Bool
    let canHideName: Bool
    let canHideForMe: Bool

    var id: String { uid }

    var hasActions: Bool { canKick || canHideName || canHideForMe }
}

struct PvPSettingRow: Sendable, Equatable, Identifiable {
    enum Field: Sendable, Equatable {
        case films
        case frames
        case timeLimit
        case health
    }

    struct Option: Sendable, Equatable, Identifiable {
        let value: Int
        let label: String

        var id: Int { value }
    }

    let field: Field
    let title: String
    let options: [Option]
    let selected: Int
    let isEditable: Bool

    var id: String { title }

    var selectedLabel: String { options.first { $0.value == selected }?.label ?? "\(selected)" }
}

enum PvPRoomChoices {
    static let films = [5, 10, 15]
    static let frames = [6, 4, 3]
    static let timeLimits = [30, 45, 60]
}

// MARK: - Builder

extension PvPScreenBuilder {
    func lobby() -> PvPLobbyScreen {
        let kind = state.kind ?? .room
        let seated = state.players.filter { !$0.left }
        return PvPLobbyScreen(
            kind: kind,
            code: state.code,
            invite: PvPRoomLink(code: state.code).map { PvPInvite(url: $0.url, text: $0.invitation(kind: kind)) },
            players: lobbyRows(),
            seats: seats(seated.count, kind: kind),
            settings: settingRows(),
            summary: settingsSummary,
            primary: lobbyAction(seated: seated),
            hint: lobbyHint(seated: seated)
        )
    }

    private func seats(_ count: Int, kind: PvPRoomKind) -> String {
        guard let max = state.settings?.maxPlayers ?? (kind == .duel ? 2 : nil) else { return PvPScreenText.players(count) }
        return "\(count) из \(max)"
    }

    private func lobbyRows() -> [PvPPlayerRow] {
        let ordered = state.players.enumerated().sorted { lhs, rhs in
            if lhs.element.isHost != rhs.element.isHost { return lhs.element.isHost }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return ordered.map { player in
            let (status, tone) = lobbyStatus(of: player)
            return playerRow(player, status: status, tone: tone)
        }
    }

    func playerRow(_ player: PvPMatchPlayer, status: String, tone: PvPPlayerRow.Tone) -> PvPPlayerRow {
        let hostsRoom = state.kind == .room && state.isHost
        let hiddenForMe = options.hiddenNames.contains(player.uid)
        return PvPPlayerRow(
            uid: player.uid,
            name: displayName(player),
            avatar: PvPAvatar(icon: player.icon, color: player.color),
            isYou: player.isYou,
            isHost: player.isHost && state.kind == .room,
            status: status,
            tone: tone,
            isNameHidden: hiddenForMe,
            canKick: hostsRoom && !player.isYou,
            canHideName: hostsRoom && !player.isYou && player.name != player.alias,
            canHideForMe: !player.isYou
        )
    }

    private func lobbyStatus(of player: PvPMatchPlayer) -> (String, PvPPlayerRow.Tone) {
        if player.left { return ("Вышел", .left) }
        switch player.connection {
        case .offline: return ("Не в сети", .offline)
        case .away: return ("Свернул приложение", .away)
        case .online: break
        }
        if state.kind == .room, player.isHost { return ("Хост", .ready) }
        return player.ready ? ("Готов", .ready) : ("Не готов", .waiting)
    }

    private func settingRows() -> [PvPSettingRow] {
        guard let settings = state.settings else { return [] }
        let editable = settings.kind == .room && state.isHost && state.phase == .lobby
        let films: PvPSettingRow = settings.kind == .duel
            ? PvPSettingRow(field: .films, title: "Длина", options: [.init(value: settings.maxFilms ?? settings.films,
                                                                            label: "до \(settings.maxFilms ?? settings.films)")],
                            selected: settings.maxFilms ?? settings.films, isEditable: false)
            : choiceRow(.films, title: "Фильмов", values: PvPRoomChoices.films, selected: settings.films, editable: editable) { "\($0)" }
        var rows = [
            films,
            choiceRow(.frames, title: "Кадров", values: PvPRoomChoices.frames, selected: settings.frames, editable: editable) { "\($0)" },
            choiceRow(.timeLimit, title: "Время", values: PvPRoomChoices.timeLimits, selected: settings.timeLimitSec, editable: editable) { "\($0) с" }
        ]
        if let hp = settings.hp {
            rows.append(PvPSettingRow(field: .health, title: "Здоровье", options: [.init(value: hp, label: "\(PvPScreenText.number(hp)) HP")],
                                      selected: hp, isEditable: false))
        }
        return rows
    }

    private func choiceRow(_ field: PvPSettingRow.Field, title: String, values: [Int], selected: Int, editable: Bool,
                           label: (Int) -> String) -> PvPSettingRow {
        let values = values.contains(selected) ? values : (values + [selected]).sorted()
        return PvPSettingRow(field: field, title: title, options: values.map { .init(value: $0, label: label($0)) },
                             selected: selected, isEditable: editable)
    }

    var settingsSummary: String {
        guard let settings = state.settings else { return "" }
        let length = settings.kind == .duel
            ? "До победы"
            : PvPScreenText.films(settings.films, mediaType: settings.mediaType)
        return [length, PvPScreenText.frames(settings.frames), "\(settings.timeLimitSec) с на фильм"].joined(separator: " · ")
    }

    private func lobbyAction(seated: [PvPMatchPlayer]) -> PvPAction {
        if state.kind == .room, state.isHost {
            return PvPAction(kind: .start, title: "Начать", isEnabled: seated.count >= 2)
        }
        if state.me?.ready == true {
            return PvPAction(kind: .unready, title: "Не готов", isEnabled: true)
        }
        return PvPAction(kind: .ready, title: "Готов", isEnabled: true)
    }

    private func lobbyHint(seated: [PvPMatchPlayer]) -> String? {
        let others = seated.filter { !$0.isYou }
        if state.kind == .duel {
            guard let rival = others.first else { return "Ждём соперника — отправьте ему код" }
            switch (state.me?.ready == true, rival.ready) {
            case (true, false): return "Ждём, когда \(displayName(rival)) нажмёт «Готов»"
            case (false, true): return "\(displayName(rival)) готов — дуэль начнётся, как только вы нажмёте «Готов»"
            default: return "Дуэль начнётся, когда оба нажмут «Готов»"
            }
        }
        if state.isHost {
            guard !others.isEmpty else { return "Нужен хотя бы ещё один игрок — отправьте код" }
            let ready = others.filter(\.ready).count
            return "Готовы \(ready) из \(others.count)"
        }
        return "Матч запускает хост"
    }
}
