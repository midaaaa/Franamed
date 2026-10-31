//
//  PvPRoomLink.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

struct PvPRoomLink: Sendable, Equatable, Hashable {
    static let scheme = "franamed"
    static let host = "pvp"
    static let alphabet = Set("0123456789")
    static let length = 6

    let code: String

    init?(code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(code) else { return nil }
        self.code = code
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == Self.host else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 1 else { return nil }
        self.init(code: String(parts[0]))
    }

    init?(text: String) {
        if let link = text.split(whereSeparator: \.isWhitespace).lazy.compactMap({ URL(string: String($0)) }).compactMap(PvPRoomLink.init(url:)).first {
            self = link
            return
        }
        let typed = Self.typed(text)
        guard typed.count == Self.length else { return nil }
        self.init(code: typed)
    }

    var url: URL {
        URL(string: "\(Self.scheme)://\(Self.host)/\(code)")!
    }

    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(alphabet.contains)
    }

    static func typed(_ text: String) -> String {
        String(text.filter(alphabet.contains).prefix(length))
    }

    func invitation(kind: PvPRoomKind) -> String {
        let call = kind == .duel
            ? "Вызываю на дуэль во Franamed — угадаем фильм по кадрам, кто быстрее."
            : "Заходи в комнату во Franamed — угадываем фильмы по кадрам."
        return "\(call)\nКод: \(code)\n\(url.absoluteString)"
    }
}
