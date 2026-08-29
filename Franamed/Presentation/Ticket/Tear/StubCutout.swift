//
//  StubCutout.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct StubCutout: Shape {
    var fullSize: CGSize
    var stubRect: CGRect

    func path(in rect: CGRect) -> Path {
        var p = Path(CGRect(origin: .zero, size: fullSize).insetBy(dx: -slack, dy: -slack))
        p.addRect(stubRect)
        return p
    }

    private let slack: CGFloat = 64
}
