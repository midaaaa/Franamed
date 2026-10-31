//
//  PvPScreenBuilder.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

struct PvPScreenBuilder {
    let state: PvPMatchState
    let now: Date
    let options: PvPScreenOptions

    static let noticeLifetime: TimeInterval = 5

    func displayName(_ player: PvPMatchPlayer) -> String {
        options.hiddenNames.contains(player.uid) ? player.alias : player.name
    }

    // MARK: Content

    func content() -> PvPScreen.Content {
        switch state.phase {
        case let .closed(closure):
            return .closed(closed(closure))
        case .connecting:
            return .connecting(connecting())
        case .lobby:
            return state.settings == nil ? .connecting(connecting()) : .lobby(lobby())
        case .loading, .ready, .countdown, .playing:
            return .match(match())
        case .reveal:
            guard let reveal = state.reveal else { return .match(match()) }
            return .reveal(self.reveal(reveal))
        case .finished:
            guard let result = state.result else { return .connecting(connecting()) }
            return .final(final(result))
        }
    }

    private func connecting() -> PvPConnectingScreen {
        let detail = state.link == .reconnecting ? "Восстанавливаем связь" : "Код \(state.code)"
        return PvPConnectingScreen(title: "Подключаемся", detail: detail)
    }

    private func closed(_ closure: PvPMatchClosure) -> PvPClosedScreen {
        let reconnect = PvPAction(kind: .reconnect, title: "Подключиться снова", isEnabled: true)
        switch closure {
        case .disconnected:
            return PvPClosedScreen(kind: .disconnected, title: "Связь потеряна", message: "Место в комнате сохранено — можно вернуться", action: reconnect)
        case let .failed(reason):
            return PvPClosedScreen(kind: .failed, title: "Не удалось подключиться", message: reason, action: reconnect)
        case .left:
            return PvPClosedScreen(kind: .left, title: "Вы вышли", message: "Комната продолжает игру без вас", action: nil)
        case .replaced:
            return PvPClosedScreen(kind: .replaced, title: "Открыто в другом месте", message: "Эта комната открыта на другом устройстве", action: nil)
        case .kicked:
            return PvPClosedScreen(kind: .kicked, title: "Вас удалили", message: "Хост удалил вас из комнаты", action: nil)
        case .roomClosed:
            return PvPClosedScreen(kind: .roomGone, title: "Комната закрыта", message: "В ней давно никого не было", action: nil)
        case .removedForFlooding:
            return PvPClosedScreen(kind: .kicked, title: "Вас отключили", message: "Слишком много сообщений подряд", action: nil)
        case let .refused(code):
            let gone = code == "room_not_found" || code == "room_closed"
            return PvPClosedScreen(kind: gone ? .roomGone : .refused, title: gone ? "Комнаты нет" : "Не пустили",
                                   message: PvPErrorText.message(code: code), action: nil)
        }
    }

    // MARK: Chrome

    func chrome() -> PvPChrome {
        let kind = state.kind
        let host = kind == .room && state.isHost
        let pausable = [.ready, .countdown, .playing, .reveal].contains(state.phase)
        return PvPChrome(
            title: kind == .duel ? "Дуэль" : "Комната",
            code: state.code,
            banners: banners(),
            canPause: host && pausable && state.pause == nil,
            canResume: host && state.pause != nil,
            leave: leave(),
            pause: pauseOverlay(),
            isAway: state.me?.connection == .away
        )
    }

    private var isMatchRunning: Bool {
        [.loading, .ready, .countdown, .playing, .reveal].contains(state.phase)
    }

    private func leave() -> PvPLeave {
        switch state.phase {
        case .closed, .connecting, .finished:
            return PvPLeave(kind: .close, title: "Закрыть", confirmation: nil, confirmTitle: "Закрыть")
        case .lobby:
            return PvPLeave(kind: .leave, title: "Выйти", confirmation: nil, confirmTitle: "Выйти")
        default:
            if state.kind == .duel {
                return PvPLeave(kind: .forfeit, title: "Сдаться",
                                confirmation: "Выход из дуэли засчитается как техническое поражение", confirmTitle: "Сдаться")
            }
            return PvPLeave(kind: .leave, title: "Выйти",
                            confirmation: "Очки сохранятся, вернуться можно по коду \(state.code)", confirmTitle: "Выйти")
        }
    }

    private func pauseOverlay() -> PvPPauseOverlay? {
        guard let pause = state.pause else { return nil }
        let host = state.players.first(where: \.isHost)
        let detail = state.isHost ? "Вы поставили игру на паузу" : "\(host.map(displayName) ?? "Хост") поставил игру на паузу"
        return PvPPauseOverlay(title: "Пауза", detail: detail,
                               autoResume: "Продолжим сами через \(PvPScreenText.clock(pause.autoResumeAt.timeIntervalSince(now)))",
                               canResume: state.isHost)
    }

    // MARK: Banners

    func banners() -> [PvPBanner] {
        var banners: [PvPBanner] = []
        switch state.link {
        case .reconnecting where state.phase != .connecting:
            banners.append(PvPBanner(id: "link", kind: .reconnecting, title: "Переподключаемся", detail: nil, isUrgent: false))
        case .polling:
            banners.append(PvPBanner(id: "link", kind: .polling, title: "Запасной канал связи",
                                     detail: "Обновления приходят раз в пару секунд", isUrgent: false))
        default:
            break
        }
        if state.kind == .duel, isMatchRunning {
            for rival in state.opponents where rival.connection != .online {
                let offline = rival.connection == .offline
                let title = offline ? "\(displayName(rival)) не в сети" : "\(displayName(rival)) свернул приложение"
                let detail = rival.forfeitAt.map { "Техническая победа через \(PvPScreenText.clock($0.timeIntervalSince(now)))" }
                banners.append(PvPBanner(id: "rival-\(rival.uid)", kind: offline ? .rivalOffline : .rivalAway,
                                         title: title, detail: detail, isUrgent: rival.forfeitAt != nil))
            }
        }
        if let notice = state.notice, now.timeIntervalSince(notice.at) < Self.noticeLifetime,
           let text = PvPErrorText.notice(code: notice.code) {
            banners.append(PvPBanner(id: "notice-\(notice.code)-\(notice.at.timeIntervalSince1970)", kind: .notice,
                                     title: text, detail: nil, isUrgent: false))
        }
        return banners
    }
}
