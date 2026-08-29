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

@MainActor
final class Haptics {
    static let shared = Haptics()

    static var isEnabled = true

    private static let minimumInterval: TimeInterval = 0.035

    #if canImport(UIKit)
    private let click = UIImpactFeedbackGenerator(style: .rigid)
    private let knit = UIImpactFeedbackGenerator(style: .soft)
    private let done = UINotificationFeedbackGenerator()
    private var lastClick = Date.distantPast
    private var lastKnit = Date.distantPast
    #endif

    func prepare() {
        #if canImport(UIKit)
        click.prepare()
        knit.prepare()
        #endif
    }

    func tabBroke() {
        #if canImport(UIKit)
        guard Self.isEnabled, allow(&lastClick) else { return }
        click.impactOccurred(intensity: 0.8)
        click.prepare()
        #endif
    }

    func tabHealed() {
        #if canImport(UIKit)
        guard Self.isEnabled, allow(&lastKnit) else { return }
        knit.impactOccurred(intensity: 0.45)
        knit.prepare()
        #endif
    }

    func completed() {
        #if canImport(UIKit)
        guard Self.isEnabled else { return }
        done.notificationOccurred(.success)
        #endif
    }

    #if canImport(UIKit)
    private func allow(_ last: inout Date) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(last) > Self.minimumInterval else { return false }
        last = now
        return true
    }
    #endif
}
