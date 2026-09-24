//
//  FlipCanvas.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.09.2026.
//

import SwiftUI
import MetalKit
import Combine

@MainActor
final class FlipFaces: ObservableObject {
    @Published private(set) var frontTexture: MTLTexture?
    @Published private(set) var backTexture: MTLTexture?
    @Published private(set) var frontImage: UIImage?
    @Published private(set) var backImage: UIImage?

    func capture(front: some View, back: some View, scale: CGFloat) {
        if let image = TicketSnapshot.image(of: front, scale: scale) {
            frontTexture = TicketSnapshot.texture(from: image) ?? frontTexture
            frontImage = UIImage(cgImage: image, scale: scale, orientation: .up)
        }
        if let image = TicketSnapshot.image(of: back, scale: scale) {
            backTexture = TicketSnapshot.texture(from: image) ?? backTexture
            backImage = UIImage(cgImage: image, scale: scale, orientation: .up)
        }
    }
}

struct FlipCanvas: View {
    let engine: TicketFlipEngine
    @ObservedObject var faces: FlipFaces
    let size: CGSize
    let edgeStyle: TicketEdgeStyle

    var body: some View {
        TicketFlipRenderer(
            engine: engine,
            frontTexture: faces.frontTexture,
            backTexture: faces.backTexture,
            stubSize: size,
            edgeStyle: edgeStyle
        )
        .frame(width: size.width + FlipLook.canvasPadding * 2,
               height: size.height + FlipLook.canvasPadding * 2)
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
