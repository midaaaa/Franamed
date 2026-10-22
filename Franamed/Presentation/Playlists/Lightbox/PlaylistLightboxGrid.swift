//
//  PlaylistLightboxGrid.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import Combine
import SwiftUI

@MainActor
final class PlaylistLightboxGrid: ObservableObject {
    struct ScrollTarget: Equatable {
        let key: String
        let isAnimated: Bool
    }

    @Published private(set) var hiddenKey: String?
    @Published private(set) var scrollTarget: ScrollTarget?

    var frames: [String: CGRect] = [:]
    var visible: CGRect = .zero

    static let scrollAnimation = Animation.smooth(duration: 0.4)
    static let scrollDuration = Duration.milliseconds(420)
    private static let swapAnimation = Animation.easeInOut(duration: 0.3)

    func isVisible(_ key: String) -> Bool {
        guard let frame = frames[key], !visible.isEmpty else { return false }
        return visible.contains(frame)
    }

    func hide(_ key: String?, isAnimated: Bool = false) {
        guard isAnimated else {
            hiddenKey = key
            return
        }
        withAnimation(Self.swapAnimation) { hiddenKey = key }
    }

    @discardableResult
    func reveal(_ key: String, isAnimated: Bool) -> Bool {
        let isShown = isAnimated ? isVisible(key) : isPartlyVisible(key)
        guard !isShown else { return false }
        scrollTarget = ScrollTarget(key: key, isAnimated: isAnimated)
        return true
    }

    func didScroll() {
        scrollTarget = nil
    }

    private func isPartlyVisible(_ key: String) -> Bool {
        guard let frame = frames[key], !visible.isEmpty else { return false }
        return visible.intersects(frame)
    }
}
