//
//  PlaylistTicketLoader.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import Combine
import UIKit

@MainActor
final class PlaylistTicketLoader: ObservableObject {
    @Published private(set) var details: [String: MediaDetails] = [:]

    private var requestedDetails: Set<String> = []
    private var shareFrames: [String: ShareFrames] = [:]
    private var shareLoads: [String: Task<ShareFrames?, Never>] = [:]
    private let facade: MediaFacadeProtocol

    init(facade: MediaFacadeProtocol = AppFactory.makeMediaFacade()) {
        self.facade = facade
    }

    func loadDetails(_ keys: [String]) {
        for key in keys where !requestedDetails.contains(key) {
            guard let ref = PlaylistMediaRef(key: key) else { continue }
            requestedDetails.insert(key)
            Task {
                if let loaded = try? await facade.fetchDetails(mediaType: ref.mediaType, id: ref.id) {
                    details[key] = loaded
                } else {
                    requestedDetails.remove(key)
                }
            }
        }
    }

    func prefetchPosters(_ urls: [URL]) {
        for url in urls where ImageCache.shared.image(for: url) == nil {
            Task {
                guard let image = await FrameDownloads.shared.image(for: url) else { return }
                ImageCache.shared.store(image, for: url)
            }
        }
    }

    func cachedShareFrames(_ key: String) -> ShareFrames? {
        shareFrames[key]
    }

    func shareFrames(for entry: PlaylistEntry, in playlistID: String) async -> ShareFrames? {
        if let frames = shareFrames[entry.key] { return frames }
        if let load = shareLoads[entry.key] { return await load.value }
        let load = Task { await loadShareFrames(for: entry, in: playlistID) }
        shareLoads[entry.key] = load
        let frames = await load.value
        shareLoads[entry.key] = nil
        if let frames { shareFrames[entry.key] = frames }
        return frames
    }

    private func loadShareFrames(for entry: PlaylistEntry, in playlistID: String) async -> ShareFrames? {
        let frameCount = PlaylistDetail.frameCount
        guard let media = try? await facade.fetchPlaylistEntry(playlistId: playlistID, mediaKey: entry.key,
                                                                 frameCount: frameCount) else { return nil }
        let urls = media.backdrops.prefix(frameCount).compactMap { URL(string: $0.filePath) }
        let answerIndex = entry.wasCorrect == true ? max(entry.attemptsUsed, 1) - 1 : frameCount - 1
        let first = await Self.frame(urls.first)
        let answer = answerIndex == 0 ? first : await Self.frame(urls[safe: answerIndex])
        return ShareFrames(first: first?.image, answer: answer?.image,
                           firstLight: first?.light ?? .dark,
                           answerLight: answer?.light ?? first?.light ?? .dark)
    }

    private static func frame(_ url: URL?) async -> (image: UIImage, light: HallFrameSample?)? {
        guard let url, let image = await FrameDownloads.shared.image(for: url) else { return nil }
        return (image, await HallFrameSample.make(image))
    }
}
