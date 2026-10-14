//
//  TextureUpload.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.10.2026.
//

import CoreGraphics
import Metal

enum TextureUpload {
    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()
    private static let bytesPerPixel = 4

    static func texture(from image: CGImage) -> MTLTexture? {
        guard let upload = encode(image) else { return nil }
        upload.commandBuffer.waitUntilCompleted()
        return upload.commandBuffer.status == .completed ? upload.texture : nil
    }

    @concurrent
    static func texture(from image: CGImage) async -> MTLTexture? {
        guard let upload = encode(image) else { return nil }
        await upload.commandBuffer.completed()
        return upload.commandBuffer.status == .completed ? upload.texture : nil
    }

    private static func encode(_ image: CGImage) -> (texture: MTLTexture, commandBuffer: MTLCommandBuffer)? {
        let width = image.width, height = image.height
        let bytesPerRow = width * bytesPerPixel
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                                  mipmapped: true)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard width > 0, height > 0, let device,
              let staging = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: staging.contents(), width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue),
              let texture = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue?.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerRow * height,
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        return (texture, commandBuffer)
    }
}
