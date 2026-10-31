//
//  PvPScreenText.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

enum PvPScreenText {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int((seconds - 0.001).rounded(.up)))
        let tail = total % 60
        return "\(total / 60):" + (tail < 10 ? "0\(tail)" : "\(tail)")
    }

    static func number(_ value: Int) -> String {
        let digits = String(abs(value))
        var groups: [String] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(String(digits[start..<end]), at: 0)
            end = start
        }
        return (value < 0 ? "−" : "") + groups.joined(separator: "\u{202F}")
    }

    static func signed(_ value: Int) -> String {
        value > 0 ? "+" + number(value) : number(value)
    }

    static func damage(_ value: Int) -> String {
        value > 0 ? "−" + number(value) : "0"
    }

    static func seconds(milliseconds: Int) -> String {
        let tenths = Int((Double(milliseconds) / 100).rounded())
        return "\(tenths / 10),\(tenths % 10) с"
    }

    static func multiplier(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return tenths % 10 == 0 ? "×\(tenths / 10)" : "×\(tenths / 10),\(tenths % 10)"
    }

    static func ordinal(_ value: Int) -> String {
        "\(value)-м"
    }

    static func frames(_ count: Int) -> String {
        "\(count) \(RussianPlural.form(count, one: "кадр", few: "кадра", many: "кадров"))"
    }

    static func films(_ count: Int, mediaType: MediaType) -> String {
        RussianPlural.titles(count, mediaType: mediaType)
    }

    static func players(_ count: Int) -> String {
        "\(count) \(RussianPlural.form(count, one: "игрок", few: "игрока", many: "игроков"))"
    }

    static func points(_ count: Int) -> String {
        "\(number(count)) \(RussianPlural.form(count, one: "очко", few: "очка", many: "очков"))"
    }

    static func title(_ mediaType: MediaType) -> String {
        mediaType == .movie ? "Фильм" : "Сериал"
    }
}
