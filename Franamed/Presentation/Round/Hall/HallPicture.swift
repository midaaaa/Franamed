//
//  HallPicture.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 08.10.2026.
//

import MetalKit
import UIKit

struct HallPicture: Equatable, @unchecked Sendable {
    let texture: MTLTexture
    let aspect: Float

    static func == (lhs: HallPicture, rhs: HallPicture) -> Bool {
        lhs.texture === rhs.texture
    }

    @concurrent
    static func make(_ image: UIImage) async -> HallPicture? {
        guard let device = HallRenderer.shared?.device, let cgImage = image.cgImage, cgImage.height > 0 else { return nil }
        let options: [MTKTextureLoader.Option: Any] = [
            .generateMipmaps: true,
            .SRGB: false,
            .textureStorageMode: MTLStorageMode.private.rawValue,
        ]
        guard let texture = try? await MTKTextureLoader(device: device).newTexture(cgImage: cgImage, options: options)
        else { return nil }
        return HallPicture(texture: texture, aspect: Float(cgImage.width) / Float(cgImage.height))
    }
}
