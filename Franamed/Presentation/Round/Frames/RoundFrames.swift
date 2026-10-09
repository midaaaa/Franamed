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
    @Published private(set) var picture: HallPicture?

    private var target: URL?
    private var images: [URL: UIImage] = [:]
    private var frameLights: [URL: HallFrameSample] = [:]
    private var pictures: [URL: HallPicture] = [:]

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

        if images[url] == nil {
            await download(url)
        } else {
            isWaiting = false
        }
        guard !Task.isCancelled else { return }
        await prepareLight(url)
        await preparePicture(url)
        guard !Task.isCancelled else { return }
        present(url)
    }

    func preload(_ urls: [URL]) async {
        let round = Set(urls)
        images = images.filter { round.contains($0.key) }
        frameLights = frameLights.filter { round.contains($0.key) }
        pictures = pictures.filter { round.contains($0.key) }
        for url in urls {
            guard !Task.isCancelled else { return }
            if images[url] == nil, let image = await FrameDownloads.shared.image(for: url) {
                guard !Task.isCancelled else { return }
                images[url] = image
            }
            await prepareLight(url)
            await preparePicture(url)
        }
    }

    private func download(_ url: URL) async {
        if displayedURL != nil { isWaiting = true }
        clearDisplayed()

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

    private func preparePicture(_ url: URL) async {
        guard pictures[url] == nil, let image = images[url] else { return }
        if let picture = await HallPicture.make(image) { pictures[url] = picture }
    }

    @concurrent
    private nonisolated static func makeLight(_ image: UIImage) async -> HallFrameSample? {
        HallFrameSample(image: image)
    }

    private func present(_ url: URL) {
        displayedURL = url
        frameLight = frameLights[url] ?? .dark
        picture = pictures[url]
        hasPresentedFrame = true
        isWaiting = false
    }

    private func clearDisplayed() {
        displayedURL = nil
        frameLight = .dark
        picture = nil
    }

    private func waitForRound(isLoading: Bool) async {
        clearDisplayed()
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
