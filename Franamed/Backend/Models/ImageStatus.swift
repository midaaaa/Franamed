//
//  ImageStatus.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum ImageStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case approved
    case rejected

    var displayName: String {
        switch self {
        case .pending: "На проверке"
        case .approved: "Одобрен"
        case .rejected: "Отклонён"
        }
    }
}
