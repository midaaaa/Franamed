//
//  ProtectedContent.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.09.2026.
//

import SwiftUI

struct ProtectedContent<Content: View>: UIViewRepresentable {

    @Environment(\.colorScheme) private var colorScheme

    let isProtected: Bool
    @ViewBuilder var content: Content

    func makeUIView(context: Context) -> ProtectedBox {
        let hosting = UIHostingController(rootView: hosted)
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = false
        hosting.safeAreaRegions = []
        context.coordinator.hosting = hosting
        return ProtectedBox(child: hosting.view)
    }

    func updateUIView(_ box: ProtectedBox, context: Context) {
        context.coordinator.hosting?.rootView = hosted
        box.isProtected = isProtected
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var hosted: AnyView {
        AnyView(content.environment(\.colorScheme, colorScheme))
    }

    @MainActor
    final class Coordinator {
        var hosting: UIHostingController<AnyView>?
    }
}
