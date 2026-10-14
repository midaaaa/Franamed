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
    let firstFrame: UIImage?
    let answerFrame: UIImage?
    let firstLight: HallFrameSample
    let answerLight: HallFrameSample
    var roundSize = CGSize(width: 393, height: 852)
    var roundFrameTop: CGFloat = 103
    var poster: UIImage?
    var isPosterPending = false
    var halls: [ShareMode: UIImage] = [:]
    var stubs: [ResultStubContent: ShareStubImage] = [:]

    static let cardFrame = CGRect(x: 0, y: 0, width: ShareFormat.baseWidth, height: ShareFormat.baseWidth * 9 / 16)

    var cardScale: CGFloat { ShareFormat.baseWidth / max(roundSize.width, 1) }

    var hallRect: CGRect {
        CGRect(x: 0, y: -roundFrameTop * cardScale, width: ShareFormat.baseWidth, height: roundSize.height * cardScale)
    }

    func picture(for mode: ShareMode) -> UIImage? {
        mode.hidesAnswer ? firstFrame : answerFrame ?? firstFrame
    }

    func light(for mode: ShareMode) -> HallFrameSample {
        mode.hidesAnswer || answerFrame == nil ? firstLight : answerLight
    }
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
        case nil: "Мне не хватило \(Self.frames(content.marks.count))"
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
    var currentStub: () -> UIImage? = { nil }
    var makeFlight: () -> FlipFlight? = { nil }
    var renderFace: (ResultStubContent) -> MTLTexture? = { _ in nil }
    var renderStub: (ResultStubContent) -> UIImage? = { _ in nil }
}

extension ShareLaunch {
    @MainActor
    init(snapshotter: FlipSnapshotter, source: CGRect, startsOnBack: Bool) {
        self.init(source: source, startsOnBack: startsOnBack,
                  presenter: { snapshotter.hostController() },
                  currentStub: { snapshotter.current() },
                  makeFlight: { snapshotter.flightRenderer() },
                  renderFace: { snapshotter.faceTexture(front: ResultStubFront(content: $0)) },
                  renderStub: { snapshotter.render(front: ResultStubFront(content: $0)) })
    }
}

extension ShareMaterial {
    static var preview: ShareMaterial {
        let item = MediaItem(id: 335984, mediaType: .movie, title: "Бегущий по лезвию 2049",
                             originalTitle: "Blade Runner 2049", releaseDate: "2017-10-04", overview: nil)
        let details = MediaDetails(runtimeMinutes: 164, firstYear: 2017, certification: "18+", authors: ["Дени Вильнёв"])
        let content = ResultStubContent(item: item, mediaType: .movie, details: details, outcome: .correct, attemptsUsed: 2,
                                        marks: ResultStubMark.live(frameCount: 6, attemptsMade: 2, revealedCount: 2,
                                                                   outcome: .correct))
        return ShareMaterial(content: content, solvedAtFrame: 2, firstFrame: nil, answerFrame: nil,
                             firstLight: .dark, answerLight: .dark)
    }
}
