//
//  ReportReason.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum ReportReason: String, Codable, Sendable, CaseIterable, Identifiable {
    case poster
    case notAFrame = "not_a_frame"
    case badQuality = "bad_quality"
    case unclear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .poster: "Это постер"
        case .notAFrame: "Не кадр из фильма"
        case .badQuality: "Плохое качество"
        case .unclear: "Непонятно, что на кадре"
        }
    }
}
