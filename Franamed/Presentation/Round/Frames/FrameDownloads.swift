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

    private var running: [URL: Task<Bool, Never>] = [:]

    nonisolated static func isPrepared(_ url: URL) -> Bool {
        ImageCache.shared.image(for: url) != nil
    }

    func prepare(_ url: URL) async -> Bool {
        if Self.isPrepared(url) { return true }
        if let task = running[url] { return await task.value }

        let task = Task { await Self.download(url) }
        running[url] = task
        let isPrepared = await task.value
        running[url] = nil
        return isPrepared
    }

    @concurrent
    private static func download(_ url: URL) async -> Bool {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = await UIImage(data: data)?.byPreparingForDisplay() else { return false }
        ImageCache.shared.store(image, for: url)
        return true
    }
}
