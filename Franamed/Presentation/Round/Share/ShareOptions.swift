//
//  ShareOptions.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import SwiftUI

enum ShareMode: CaseIterable {
    case answer
    case riddle

    var hidesAnswer: Bool { self == .riddle }

    func stub(of content: ResultStubContent) -> ResultStubContent {
        hidesAnswer ? content.concealed() : content
    }
}

enum ShareBackground: CaseIterable, Identifiable {
    case hall
    case poster
    case black

    var id: Self { self }

    func shown(in mode: ShareMode, material: ShareMaterial) -> ShareBackground {
        isAvailable(in: mode, material: material) ? self : .hall
    }

    func isAvailable(in mode: ShareMode, material: ShareMaterial) -> Bool {
        switch self {
        case .hall, .black: true
        case .poster: mode == .answer && (material.poster != nil || material.isPosterPending)
        }
    }
}

enum ShareFormat: CaseIterable, Identifiable {
    case story
    case square
    case sticker

    var id: Self { self }

    static let baseWidth: CGFloat = 360

    @MainActor
    var aspect: CGFloat { canvas.height / canvas.width }

    @MainActor
    var canvas: CGSize {
        switch self {
        case .story: CGSize(width: Self.baseWidth, height: Self.baseWidth * 16 / 9)
        case .square: CGSize(width: Self.baseWidth, height: Self.baseWidth)
        case .sticker:
            CGSize(width: Self.baseWidth, height: Self.baseWidth * ShareStubPlacement.stubAspect / ShareStubPlacement.stickerShare)
        }
    }
}
