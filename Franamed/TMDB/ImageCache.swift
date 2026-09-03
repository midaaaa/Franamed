//
//  ImageCache.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import Foundation
import UIKit

final class ImageCache: @unchecked Sendable {
    nonisolated static let shared = ImageCache()
    private nonisolated(unsafe) let cache = NSCache<NSURL, UIImage>()

    nonisolated func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    nonisolated func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
