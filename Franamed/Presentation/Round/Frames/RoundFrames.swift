//
//  RoundFrames.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import Combine
import Foundation
import UIKit

@MainActor
final class RoundFrames: ObservableObject {
    @Published private(set) var displayedURL: URL?
    @Published private(set) var stripTints: [ProjectorStripTint] = []
    @Published private(set) var isFillLit = false
    @Published private(set) var isWaiting = false
    @Published private(set) var hallSample: HallFrameSample = .dark

    private var target: URL?
    private var hallSamples: [URL: HallFrameSample] = [:]

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
            hallSample = hallSamples[url] ?? .dark
            isWaiting = false
            if !FrameDownloads.isPrepared(url) {
                _ = await FrameDownloads.shared.prepare(url)
                guard !Task.isCancelled else { return }
            }
            await prepareHallSample(url)
            guard !Task.isCancelled else { return }
            present(url)
            return
        }

        if displayedURL != nil { isWaiting = true }
        displayedURL = nil
        hallSample = .dark
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
        await prepareHallSample(url)
        guard !Task.isCancelled else { return }
        present(url)
    }

    func preload(_ urls: [URL]) async {
        for url in urls {
            guard !Task.isCancelled else { return }
            _ = await FrameDownloads.shared.prepare(url)
            await prepareHallSample(url)
        }
    }

    private func prepareHallSample(_ url: URL) async {
        guard hallSamples[url] == nil, let image = ImageCache.shared.image(for: url) else { return }
        if let sample = await Self.makeHallSample(image) { hallSamples[url] = sample }
    }

    @concurrent
    private nonisolated static func makeHallSample(_ image: UIImage) async -> HallFrameSample? {
        HallFrameSample(image: image)
    }

    private func present(_ url: URL) {
        displayedURL = url
        stripTints = ProjectorFrameTint.cachedTints(for: url) ?? []
        hallSample = hallSamples[url] ?? .dark
        isFillLit = true
        isWaiting = false
    }

    private func waitForRound(isLoading: Bool) async {
        displayedURL = nil
        stripTints = []
        hallSample = .dark
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
