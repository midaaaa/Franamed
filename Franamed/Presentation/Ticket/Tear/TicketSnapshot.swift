//
//  TicketSnapshot.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI
import Metal
import QuartzCore

enum TicketSnapshot {
    @MainActor
    static func texture(of content: some View, scale: CGFloat) -> MTLTexture? {
        #if DEBUG
        let started = CACurrentMediaTime()
        defer {
            let ms = (CACurrentMediaTime() - started) * 1000
            if ms > 4 { NSLog("[TicketSnapshot] %.1f ms", ms) }
        }
        #endif

        return image(of: content, scale: scale).flatMap(texture(from:))
    }

    @MainActor
    static func image(of content: some View, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.cgImage
    }

    @MainActor
    static func texture(from image: CGImage) -> MTLTexture? {
        TextureUpload.texture(from: image)
    }
}
