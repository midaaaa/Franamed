//
//  Haptics.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum HapticEvent {
    case tabBreak
    case tabHeal
    case answerCorrect
    case answerWrong

    fileprivate var isRepeating: Bool { self == .tabBreak || self == .tabHeal }
}

@MainActor
final class Haptics {
    static let shared = Haptics()

    static let enabledKey = "hapticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static let minimumInterval: TimeInterval = 0.035

    #if canImport(UIKit)
    private let selection = UISelectionFeedbackGenerator()
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    private var lastPlayed: [HapticEvent: Date] = [:]
    #endif

    func prepare() {
        #if canImport(UIKit)
        selection.prepare()
        soft.prepare()
        #endif
    }

    func play(_ event: HapticEvent) {
        guard Self.isEnabled else { return }
        #if canImport(UIKit)
        if event.isRepeating {
            let now = Date()
            if let last = lastPlayed[event], now.timeIntervalSince(last) <= Self.minimumInterval { return }
            lastPlayed[event] = now
        }

        switch event {
        case .tabBreak:
            selection.selectionChanged()
            selection.prepare()
        case .tabHeal:
            soft.impactOccurred(intensity: 0.45)
            soft.prepare()
        case .answerCorrect:
            notification.notificationOccurred(.success)
        case .answerWrong:
            notification.notificationOccurred(.error)
        }
        #endif
    }
}
