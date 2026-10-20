//
//  WindowGeometry.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI
import UIKit

struct WindowGeometry: Equatable {
    var size: CGSize = .zero
    var safeAreaInsets = EdgeInsets()
}

extension EnvironmentValues {
    @Entry var windowGeometry = WindowGeometry()
}

private struct WindowGeometryProvider: ViewModifier {
    @State private var geometry = WindowGeometry()

    func body(content: Content) -> some View {
        content
            .environment(\.windowGeometry, geometry)
            .background {
                Color.clear
                    .onGeometryChange(for: WindowGeometry.self) { proxy in
                        let insets = proxy.safeAreaInsets
                        return WindowGeometry(
                            size: CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                         height: proxy.size.height + insets.top + insets.bottom),
                            safeAreaInsets: insets)
                    } action: { geometry = $0 }
                    .ignoresSafeArea(.keyboard)
            }
    }
}

extension View {
    func providesWindowGeometry() -> some View {
        modifier(WindowGeometryProvider())
    }
}

final class WindowReference {
    weak var window: UIWindow?
}

struct WindowReader: UIViewRepresentable {
    let reference: WindowReference

    func makeUIView(context: Context) -> Probe {
        Probe(reference: reference)
    }

    func updateUIView(_ probe: Probe, context: Context) {}

    final class Probe: UIView {
        private let reference: WindowReference

        init(reference: WindowReference) {
            self.reference = reference
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reference.window = window
        }
    }
}
