//
//  TicketSnapshot.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI
import MetalKit
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

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let rendered = renderer.cgImage,
              let normalized = normalized(rendered),
              let device = MTLCreateSystemDefaultDevice() else { return nil }

        return try? MTKTextureLoader(device: device).newTexture(cgImage: normalized, options: [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft,
            .generateMipmaps: true
        ])
    }

    private static func normalized(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
