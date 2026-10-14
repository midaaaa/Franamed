//
//  ShareExport.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import CoreImage
import UIKit

enum ShareExport {
    @MainActor
    static func item(card: ShareCard) -> Any? {
        guard let image = card.image() else { return nil }
        let transparent = card.format == .sticker
        return file(image, transparent: transparent) ?? image
    }

    private static func file(_ image: UIImage, transparent: Bool) -> URL? {
        guard let data = transparent ? image.pngData() : image.jpegData(compressionQuality: 0.92) else { return nil }
        let url = URL.temporaryDirectory.appending(path: transparent ? "Franamed.png" : "Franamed.jpg")
        return (try? data.write(to: url)).map { url }
    }
}

enum SharePosterBackdrop {
    static let targetLuminance: CGFloat = 0.25
    private static let baseGain: CGFloat = 0.45
    private static let saturation = 1.1
    private static let stubBand = CGSize(width: 0.7, height: 0.4)
    private static let maxHeight: CGFloat = 1920
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    @concurrent
    static func make(_ poster: UIImage) async -> UIImage? {
        guard let source = poster.cgImage.map(CIImage.init(cgImage:)) else { return nil }
        let gain = min(targetLuminance / max(luminance(of: source, in: band(of: source.extent)), 0.01), baseGain)
        let scale = min(maxHeight / source.extent.height, 1)
        let adjusted = source
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
            ])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
        return context.createCGImage(adjusted, from: adjusted.extent.integral).map { UIImage(cgImage: $0) }
    }

    private static func band(of extent: CGRect) -> CGRect {
        extent.insetBy(dx: extent.width * (1 - stubBand.width) / 2, dy: extent.height * (1 - stubBand.height) / 2)
    }

    private static func luminance(of image: CIImage, in rect: CGRect) -> CGFloat {
        let area = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let average = area.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: CGRect(origin: .zero, size: rect.size)),
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return (0.2126 * CGFloat(pixel[0]) + 0.7152 * CGFloat(pixel[1]) + 0.0722 * CGFloat(pixel[2])) / 255
    }
}
