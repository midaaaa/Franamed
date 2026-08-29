//
//  StubSide.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import Foundation

nonisolated enum StubSide: Sendable, Equatable {
    case leading, trailing, top, bottom

    var isVertical: Bool { self == .leading || self == .trailing }
}
