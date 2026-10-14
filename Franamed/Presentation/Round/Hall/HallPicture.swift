//
//  HallPicture.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 08.10.2026.
//

import Metal
import UIKit

struct HallPicture: Equatable, @unchecked Sendable {
    let texture: MTLTexture
    let aspect: Float

    static func == (lhs: HallPicture, rhs: HallPicture) -> Bool {
        lhs.texture === rhs.texture
    }

    @concurrent
    static func make(_ image: UIImage) async -> HallPicture? {
        guard let cgImage = image.cgImage, let texture = await TextureUpload.texture(from: cgImage) else { return nil }
        return HallPicture(texture: texture, aspect: Float(cgImage.width) / Float(cgImage.height))
    }
}
