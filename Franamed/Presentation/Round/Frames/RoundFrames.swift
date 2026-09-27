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
    @Published private(set) var isWaiting = false
    @Published private(set) var hasPresentedFrame = false
    @Published private var frameLight: HallFrameSample = .dark

    private var target: URL?
    private var images: [URL: UIImage] = [:]
    private var frameLights: [URL: HallFrameSample] = [:]

    private static let spinnerDelay = Duration.milliseconds(180)
    private static let retryCap = Duration.seconds(2)

    var displayedImage: UIImage? {
        displayedURL.flatMap { images[$0] }
    }

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

        if images[url] == nil {
            await download(url)
        } else {
            isWaiting = false
        }
        guard !Task.isCancelled else { return }
        await prepareLight(url)
        guard !Task.isCancelled else { return }
        present(url)
    }

    func preload(_ urls: [URL]) async {
        let round = Set(urls)
        images = images.filter { round.contains($0.key) }
        frameLights = frameLights.filter { round.contains($0.key) }
        for url in urls {
            guard !Task.isCancelled else { return }
            if images[url] == nil, let image = await FrameDownloads.shared.image(for: url) {
                guard !Task.isCancelled else { return }
                images[url] = image
            }
            await prepareLight(url)
        }
    }

    private func download(_ url: URL) async {
        if displayedURL != nil { isWaiting = true }
        displayedURL = nil
        frameLight = .dark

        let spinner = Task {
            try? await Task.sleep(for: Self.spinnerDelay)
            guard !Task.isCancelled, target == url else { return }
            isWaiting = true
        }
        defer { spinner.cancel() }

        var attempt = 0
        while !Task.isCancelled {
            if let image = await FrameDownloads.shared.image(for: url) {
                if !Task.isCancelled { images[url] = image }
                return
            }
            isWaiting = true
            attempt += 1
            try? await Task.sleep(for: min(.milliseconds(400 * attempt), Self.retryCap))
        }
    }

    private func prepareLight(_ url: URL) async {
        guard frameLights[url] == nil, let image = images[url] else { return }
        if let light = await Self.makeLight(image) { frameLights[url] = light }
    }

    @concurrent
    private nonisolated static func makeLight(_ image: UIImage) async -> HallFrameSample? {
        HallFrameSample(image: image)
    }

    private func present(_ url: URL) {
        displayedURL = url
        frameLight = frameLights[url] ?? .dark
        hasPresentedFrame = true
        isWaiting = false
    }

    private func waitForRound(isLoading: Bool) async {
        displayedURL = nil
        frameLight = .dark
        hasPresentedFrame = false
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
