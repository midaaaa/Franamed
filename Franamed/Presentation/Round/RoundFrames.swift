//
//  RoundFrames.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import Combine
import Foundation

@MainActor
final class RoundFrames: ObservableObject {
    @Published private(set) var displayedURL: URL?
    @Published private(set) var stripTints: [ProjectorStripTint] = []
    @Published private(set) var isFillLit = false
    @Published private(set) var isWaiting = false

    private var target: URL?

    private static let spinnerDelay = Duration.milliseconds(180)
    private static let retryLimit = 4

    func show(_ url: URL?, isRoundLoading: Bool) async {
        target = url
        guard let url else {
            await waitForRound(isLoading: isRoundLoading)
            return
        }
        guard url != displayedURL else { return }

        if ImageCache.shared.image(for: url) != nil {
            displayedURL = url
            isWaiting = false
            if !FrameDownloads.isPrepared(url) {
                _ = await FrameDownloads.shared.prepare(url)
                guard !Task.isCancelled else { return }
            }
            present(url)
            return
        }

        if displayedURL != nil { isWaiting = true }
        displayedURL = nil
        isFillLit = false

        let spinner = Task {
            try? await Task.sleep(for: Self.spinnerDelay)
            guard !Task.isCancelled, target == url else { return }
            isWaiting = true
        }
        defer { spinner.cancel() }

        var attempt = 0
        while await !FrameDownloads.shared.prepare(url), attempt < Self.retryLimit, !Task.isCancelled {
            isWaiting = true
            attempt += 1
            try? await Task.sleep(for: .milliseconds(400 * attempt))
        }
        guard !Task.isCancelled else { return }
        present(url)
    }

    func preload(_ urls: [URL]) async {
        for url in urls {
            guard !Task.isCancelled else { return }
            _ = await FrameDownloads.shared.prepare(url)
        }
    }

    private func present(_ url: URL) {
        displayedURL = url
        stripTints = ProjectorFrameTint.cachedTints(for: url) ?? []
        isFillLit = true
        isWaiting = false
    }

    private func waitForRound(isLoading: Bool) async {
        displayedURL = nil
        stripTints = []
        isFillLit = false
        guard isLoading else {
            isWaiting = false
            return
        }
        guard !isWaiting else { return }
        try? await Task.sleep(for: Self.spinnerDelay)
        guard !Task.isCancelled else { return }
        isWaiting = true
    }
}
