//
//  ProjectorFrameTint.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.08.2026.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct ProjectorStripTint {
    let color: Color
    let brightness: Double
}

enum ProjectorFrameTint {
    nonisolated static func averageStripTints(from image: UIImage, stripCount: Int) -> [ProjectorStripTint] {
        guard stripCount > 0, let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return [] }

        let stripWidth = extent.width / CGFloat(stripCount)
        return (0..<stripCount).map { index in
            let rect = CGRect(x: extent.minX + CGFloat(index) * stripWidth, y: extent.minY, width: stripWidth, height: extent.height)
            let filter = CIFilter.areaAverage()
            filter.inputImage = ciImage
            filter.extent = rect
            guard let output = filter.outputImage else { return ProjectorStripTint(color: .white, brightness: 0) }

            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(
                output,
                toBitmap: &bitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )

            let raw = UIColor(
                red: CGFloat(bitmap[0]) / 255,
                green: CGFloat(bitmap[1]) / 255,
                blue: CGFloat(bitmap[2]) / 255,
                alpha: 1
            )
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            raw.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let vividSaturation = min(1, saturation * 1.4 + 0.05)
            let vividColor = UIColor(hue: hue, saturation: vividSaturation, brightness: max(brightness, 0.35), alpha: 1)

            return ProjectorStripTint(color: Color(vividColor), brightness: Double(brightness))
        }
    }

    nonisolated static func loadAndSample(url: URL, stripCount: Int) async -> [ProjectorStripTint] {
        if let cached = ImageCache.shared.image(for: url) {
            return averageStripTints(from: cached, stripCount: stripCount)
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return [] }
        ImageCache.shared.store(image, for: url)
        return averageStripTints(from: image, stripCount: stripCount)
    }
}
