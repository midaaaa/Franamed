//
//  ShareMaterial.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import Metal
import SwiftUI

struct ShareMaterial {
    let content: ResultStubContent
    let solvedAtFrame: Int?
    var frames: ShareFrames
    var isFramePending = false
    var roundSize = CGSize(width: 393, height: 852)
    var stubWidth = TicketStyle.referenceWidth
    var poster: UIImage?
    var isPosterPending = false
    var halls: [ShareMode: UIImage] = [:]
    var stubs: [ResultStubContent: ShareStubImage] = [:]

    static let cardFrame = CGRect(x: 0, y: 0, width: ShareFormat.baseWidth, height: ShareFormat.baseWidth * 9 / 16)

    static let hallSize = CGSize(width: ShareFormat.baseWidth, height: ShareFormat.baseWidth * 16 / 9)

    func picture(for mode: ShareMode) -> UIImage? {
        mode.hidesAnswer ? frames.first : frames.answer ?? frames.first
    }

    func light(for mode: ShareMode) -> HallFrameSample {
        mode.hidesAnswer || frames.answer == nil ? frames.firstLight : frames.answerLight
    }
}

struct ShareFrames {
    var first: UIImage?
    var answer: UIImage?
    var firstLight: HallFrameSample
    var answerLight: HallFrameSample

    static let dark = ShareFrames(firstLight: .dark, answerLight: .dark)
}

// MARK: Challenge

extension ShareMaterial {
    var challengeTitle: String {
        switch solvedAtFrame {
        case nil: "Угадаешь?"
        case 1: "Угадаешь с первого кадра?"
        default: "Угадаешь быстрее?"
        }
    }

    var challengeLine: String {
        switch solvedAtFrame {
        case nil: "Мне не хватило \(Self.frames(content.progress.frameCount))"
        case 1: "Мне хватило одного"
        case let frame?: "Мне хватило \(Self.frames(frame))"
        }
    }

    private static func frames(_ count: Int) -> String {
        let singular = count % 10 == 1 && count % 100 != 11
        return "\(count) \(singular ? "кадра" : "кадров")"
    }
}

struct ShareStubImage {
    let face: UIImage
    let shadowed: UIImage

    @MainActor
    init(face: UIImage) {
        self.face = face
        shadowed = ShareStubShadow.apply(face)
    }
}

struct ShareLaunch {
    let source: CGRect
    let startsOnBack: Bool
    var presenter: () -> UIViewController? = { nil }
    var makeFlight: () -> FlipFlight? = { nil }
    var renderFace: (ResultStubContent) -> MTLTexture? = { _ in nil }
    var renderStub: (ResultStubContent) -> UIImage? = { _ in nil }
    var stubFrame: () -> CGRect? = { nil }
    var launchStubFrame: CGRect?

    func currentSource() -> CGRect {
        guard let base = launchStubFrame, base.width > 0, base.height > 0, let now = stubFrame() else { return source }
        let sx = now.width / base.width, sy = now.height / base.height
        return CGRect(x: now.minX + (source.minX - base.minX) * sx, y: now.minY + (source.minY - base.minY) * sy,
                      width: source.width * sx, height: source.height * sy)
    }
}

extension ShareLaunch {
    @MainActor
    init(snapshotter: FlipSnapshotter, source: CGRect, startsOnBack: Bool, stubWidth: CGFloat) {
        self.init(source: source, startsOnBack: startsOnBack,
                  presenter: { snapshotter.hostController() },
                  makeFlight: { snapshotter.flightRenderer() },
                  renderFace: {
                      snapshotter.faceTexture(front: ResultStubFront(content: $0).environment(\.resultStubWidth, stubWidth))
                  },
                  renderStub: {
                      snapshotter.render(front: ResultStubFront(content: $0).environment(\.resultStubWidth, stubWidth))
                  },
                  stubFrame: { snapshotter.frameInWindow() },
                  launchStubFrame: snapshotter.frameInWindow())
    }
}

extension ShareMaterial {
    static var preview: ShareMaterial {
        let item = MediaItem(id: 335984, mediaType: .movie, title: "Бегущий по лезвию 2049",
                             originalTitle: "Blade Runner 2049", releaseDate: "2017-10-04", overview: nil)
        let details = MediaDetails(runtimeMinutes: 164, firstYear: 2017, certification: "18+", authors: ["Дени Вильнёв"])
        let content = ResultStubContent(item: item, mediaType: .movie, details: details, outcome: .correct, attemptsUsed: 2,
                                        progress: .finished(frameCount: 6, attemptsMade: 2, outcome: .correct))
        return ShareMaterial(content: content, solvedAtFrame: 2, frames: .dark)
    }
}
