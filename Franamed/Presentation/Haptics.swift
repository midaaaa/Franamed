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
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
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
            pair(rigid, first: 0.5, second: 0.85, gap: .milliseconds(90))
        case .answerWrong:
            pair(heavy, first: 0.8, second: 0.45, gap: .milliseconds(120))
        }
        #endif
    }

    #if canImport(UIKit)
    private func pair(_ generator: UIImpactFeedbackGenerator, first: CGFloat, second: CGFloat, gap: Duration) {
        generator.impactOccurred(intensity: first)
        generator.prepare()
        Task { @MainActor in
            try? await Task.sleep(for: gap)
            generator.impactOccurred(intensity: second)
        }
    }
    #endif
}
