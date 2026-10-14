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

    private var images: [URL: UIImage] = [:]
    private var frameLights: [URL: HallFrameSample] = [:]
    private var pictures: [URL: HallPicture] = [:]

    private static let retryCap = Duration.seconds(2)

    var hallLight: HallFrameSample {
        displayedURL == nil && isWaiting ? SpinnerGlyph.hallLight : frameLight
    }

    func show(_ url: URL?, isRoundLoading: Bool) async {
        guard let url else {
            waitForRound(isLoading: isRoundLoading)
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

    func image(for url: URL) -> UIImage? {
        images[url]
    }

    func light(for url: URL) -> HallFrameSample? {
        frameLights[url]
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
        isWaiting = true
        clearDisplayed()

        var attempt = 0
        while !Task.isCancelled {
            if let image = await FrameDownloads.shared.image(for: url) {
                if !Task.isCancelled { images[url] = image }
                return
            }
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

    private func waitForRound(isLoading: Bool) {
        clearDisplayed()
        hasPresentedFrame = false
        isWaiting = isLoading
    }
}
