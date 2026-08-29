//
//  TearPhase.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import Foundation

enum TearPhase {
    case rest
    case arming
    case tearing
    case detached
    case gone
    case returning
    case healing

    var showsShader: Bool { self != .rest && self != .gone && self != .returning }

    var cutsOutStub: Bool { self != .rest && self != .arming }

    var hidesLiveStub: Bool { self == .gone || self == .returning || self == .healing }

    func flattensContent(rasterizing: Bool) -> Bool {
        (cutsOutStub || rasterizing) && self != .detached && !hidesLiveStub
    }
}
