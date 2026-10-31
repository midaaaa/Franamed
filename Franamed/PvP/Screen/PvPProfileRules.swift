//
//  PvPProfileRules.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

enum PvPProfileRules {
    static let icons = ["popcorn", "clapper", "camera", "film", "ticket", "glasses3d",
                        "seat", "spotlight", "masks", "megaphone", "star", "projector"]
    static let colors = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink"]

    static let nameLength = 3...16

    enum NameCheck: Sendable, Equatable {
        case valid
        case tooShort
        case tooLong
        case badCharacters
    }

    static func check(name: String) -> NameCheck {
        let allowed = name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
        }
        guard allowed else { return .badCharacters }
        if name.count < nameLength.lowerBound { return .tooShort }
        if name.count > nameLength.upperBound { return .tooLong }
        return .valid
    }

    static func hint(for check: NameCheck) -> String? {
        switch check {
        case .valid: nil
        case .tooShort: "Хотя бы 3 символа"
        case .tooLong: "Не больше 16 символов"
        case .badCharacters: "Только латиница, цифры и _"
        }
    }
}
