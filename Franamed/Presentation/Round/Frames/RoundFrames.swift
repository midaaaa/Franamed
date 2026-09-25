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
    @Published private(set) var hasPresentedFrame = false
    @Published private var frameLight: HallFrameSample = .dark

    private var target: URL?
    private var frameLights: [URL: HallFrameSample] = [:]

    private static let spinnerDelay = Duration.milliseconds(180)
    private static let retryCap = Duration.seconds(2)

    var hallLight: HallFrameSample {
        displayedURL == nil && isWaiting ? SpinnerGlyph.hallLight : frameLight
    }

    func show(_ url: URL?, isRoundLoading: Bool) async {
        target = url
        guard let url else {
            await waitForRound(isLoading: isRoundLoading)
            return
        }
        guard url != displayedURL else { return }

        if ImageCache.shared.image(for: url) == nil {
            await download(url)
        } else {
            isWaiting = false
            if !FrameDownloads.isPrepared(url) { _ = await FrameDownloads.shared.prepare(url) }
        }
        guard !Task.isCancelled else { return }
        await prepareLight(url)
        guard !Task.isCancelled else { return }
        present(url)
    }

    func preload(_ urls: [URL]) async {
        for url in urls {
            guard !Task.isCancelled else { return }
            _ = await FrameDownloads.shared.prepare(url)
            await prepareLight(url)
        }
    }

    private func download(_ url: URL) async {
        if displayedURL != nil { isWaiting = true }
        displayedURL = nil
        frameLight = .dark
        isFillLit = false

        let spinner = Task {
            try? await Task.sleep(for: Self.spinnerDelay)
            guard !Task.isCancelled, target == url else { return }
            isWaiting = true
        }
        defer { spinner.cancel() }

        var attempt = 0
        while await !FrameDownloads.shared.prepare(url), !Task.isCancelled {
            isWaiting = true
            attempt += 1
            try? await Task.sleep(for: min(.milliseconds(400 * attempt), Self.retryCap))
        }
    }

    private func prepareLight(_ url: URL) async {
        guard frameLights[url] == nil, let image = ImageCache.shared.image(for: url) else { return }
        if let light = await Self.makeLight(image) { frameLights[url] = light }
    }

    @concurrent
    private nonisolated static func makeLight(_ image: UIImage) async -> HallFrameSample? {
        HallFrameSample(image: image)
    }

    private func present(_ url: URL) {
        displayedURL = url
        stripTints = ProjectorFrameTint.cachedTints(for: url) ?? []
        frameLight = frameLights[url] ?? .dark
        hasPresentedFrame = true
        isFillLit = true
        isWaiting = false
    }

    private func waitForRound(isLoading: Bool) async {
        displayedURL = nil
        stripTints = []
        frameLight = .dark
        hasPresentedFrame = false
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
