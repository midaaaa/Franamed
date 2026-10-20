//
//  FrameDownloads.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import Foundation
import UIKit

actor FrameDownloads {
    static let shared = FrameDownloads()

    private var running: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL, fittingPixelWidth maxWidth: CGFloat? = nil) async -> UIImage? {
        if let task = running[url] { return await task.value }

        let task = Task { await Self.download(url, fittingPixelWidth: maxWidth) }
        running[url] = task
        let image = await task.value
        running[url] = nil
        return image
    }

    @concurrent
    private static func download(_ url: URL, fittingPixelWidth maxWidth: CGFloat?) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        let pixelWidth = image.size.width * image.scale
        guard let maxWidth, pixelWidth > maxWidth else { return await image.byPreparingForDisplay() }
        let ratio = maxWidth / pixelWidth
        let size = CGSize(width: (image.size.width * ratio).rounded(), height: (image.size.height * ratio).rounded())
        return await image.byPreparingThumbnail(ofSize: size)
    }
}
