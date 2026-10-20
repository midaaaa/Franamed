//
//  WindowSizeRestrictions.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 20.10.2026.
//

import SwiftUI
import UIKit

struct WindowSizeRestrictions: UIViewRepresentable {
    let minimumSize: CGSize

    func makeUIView(context: Context) -> Probe {
        Probe(minimumSize: minimumSize)
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.minimumSize = minimumSize
    }

    final class Probe: UIView {
        var minimumSize: CGSize {
            didSet { apply() }
        }

        init(minimumSize: CGSize) {
            self.minimumSize = minimumSize
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            window?.windowScene?.sizeRestrictions?.minimumSize = minimumSize
        }
    }
}
