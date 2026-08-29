//
//  AppAppearance.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 26.08.2026.
//

import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system, light, dark

    static let storageKey = "appAppearance"

    var displayName: String {
        switch self {
        case .system: "Система"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
