//
//  PvPFrameDownloadsPreloader.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

struct PvPFrameDownloadsPreloader: PvPFramePreloader {
    private static let attempts = 3
    private static let retryStep = Duration.milliseconds(500)

    func preload(frames: [PvPFrame], spares: [PvPFrame]) async -> PvPFramePreload {
        let broken = await withTaskGroup(of: Int?.self) { group in
            for (index, frame) in frames.enumerated() {
                group.addTask { await Self.load(PvPImageLinks.frame(frame.path)) ? nil : index }
            }
            var broken: [Int] = []
            for await index in group {
                if let index { broken.append(index) }
            }
            return broken
        }
        guard !Task.isCancelled else { return .ready }
        if let first = broken.min() { return .broken(index: first) }
        Task.detached(priority: .utility) {
            for spare in spares { _ = await Self.load(PvPImageLinks.frame(spare.path)) }
        }
        return .ready
    }

    private static func load(_ url: URL?) async -> Bool {
        guard let url else { return false }
        if ImageCache.shared.image(for: url) != nil { return true }
        for attempt in 1...attempts {
            guard !Task.isCancelled else { return false }
            if let image = await FrameDownloads.shared.image(for: url) {
                ImageCache.shared.store(image, for: url)
                return true
            }
            if attempt < attempts { try? await Task.sleep(for: retryStep * attempt) }
        }
        return false
    }
}
