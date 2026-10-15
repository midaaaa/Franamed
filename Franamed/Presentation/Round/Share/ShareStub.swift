//
//  ShareStub.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.10.2026.
//

import SwiftUI

struct ShareStub: View {
    let content: ResultStubContent
    var image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width, height: image.size.height)
        } else {
            ResultStubFront(content: content)
        }
    }
}

struct ShareStubPose: ViewModifier {
    let placement: ShareStubPlacement

    func body(content: Content) -> some View {
        content
            .scaleEffect(placement.width / ResultStubMetrics.width)
            .rotationEffect(placement.angle)
            .position(placement.center)
    }
}

enum ShareStubShadow {
    private static let radius: CGFloat = 12
    private static let opacity = 0.32
    private static let drop: CGFloat = 7
    static let padding: CGFloat = 2 * radius + drop

    @MainActor
    static func apply(_ image: UIImage) -> UIImage {
        let shadowed = Image(uiImage: image)
            .shadow(color: .black.opacity(opacity), radius: radius, y: drop)
            .padding(padding)
        return render(shadowed, scale: image.scale) ?? image
    }

    @MainActor
    static func shadowOnly(_ image: UIImage) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let mask = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: image.size), blendMode: .sourceIn)
        }
        let shadow = Image(uiImage: mask)
            .blur(radius: radius)
            .opacity(opacity)
            .offset(y: drop)
            .padding(padding)
        return render(shadow, scale: image.scale)
    }

    @MainActor
    private static func render(_ content: some View, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.uiImage
    }
}
