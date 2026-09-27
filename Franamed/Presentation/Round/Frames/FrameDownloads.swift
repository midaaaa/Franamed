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

    func image(for url: URL) async -> UIImage? {
        if let task = running[url] { return await task.value }

        let task = Task { await Self.download(url) }
        running[url] = task
        let image = await task.value
        running[url] = nil
        return image
    }

    @concurrent
    private static func download(_ url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return await UIImage(data: data)?.byPreparingForDisplay()
    }
}
