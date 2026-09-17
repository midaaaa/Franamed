//
//  ProtectedImage.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.09.2026.
//

import SwiftUI

struct ProtectedImage: UIViewRepresentable {

    let image: UIImage?
    let isProtected: Bool

    func makeUIView(context: Context) -> ProtectedBox {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        context.coordinator.imageView = imageView
        return ProtectedBox(child: imageView)
    }

    func updateUIView(_ box: ProtectedBox, context: Context) {
        context.coordinator.imageView?.image = image
        box.isProtected = isProtected
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var imageView: UIImageView?
    }
}
