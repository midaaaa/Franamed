//
//  WindowMetrics.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import UIKit

enum WindowMetrics {
    @MainActor
    static var size: CGSize {
        UIApplication.shared.connectedScenes
            .lazy
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.bounds.size ?? .zero
    }
}
