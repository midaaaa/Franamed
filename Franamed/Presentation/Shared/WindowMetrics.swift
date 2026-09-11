//
//  WindowMetrics.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import UIKit

enum WindowMetrics {
    @MainActor
    static var size: CGSize { keyWindow?.bounds.size ?? .zero }

    @MainActor
    static var safeAreaInsets: UIEdgeInsets { keyWindow?.safeAreaInsets ?? .zero }

    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .lazy
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow
    }
}
