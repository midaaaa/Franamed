//
//  PvPErrorText.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

enum PvPErrorText {
    static func message(code: String) -> String {
        switch code {
        case "room_not_found": "Комнаты с таким кодом нет. Проверьте код"
        case "room_closed": "Комната уже закрылась"
        case "room_full": "В комнате нет свободных мест"
        case "match_running": "Дуэль уже идёт — войти можно только до старта"
        case "kicked": "Хост удалил вас из этой комнаты"
        case "pvp_disabled": "Игра с друзьями временно выключена"
        case "media_type_disabled": "Этот тип пока недоступен"
        case "token_invalid": "Приглашение устарело — войдите по коду ещё раз"
        case "name_rejected": "Такой ник нельзя. Попробуйте другой или 🎲"
        case "no_free_code": "Не нашли свободный код, попробуйте ещё раз"
        default: "Что-то пошло не так. Попробуйте ещё раз"
        }
    }

    static func notice(code: String) -> String? {
        switch code {
        case "not_enough_players": "Нужно хотя бы два игрока"
        case "pool_empty": "Сейчас нечего играть — попробуйте позже"
        case "paused": "Игра на паузе"
        case "no_spare": "Кадр не загрузился, а запасных не осталось"
        case "not_host": "Это может только хост"
        case "not_started": "Фильм ещё не начался"
        default: nil
        }
    }
}
