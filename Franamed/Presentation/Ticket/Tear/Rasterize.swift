//
//  Rasterize.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct Rasterize: ViewModifier {
    let isActive: Bool

    private let bleed: CGFloat = 2

    func body(content: Content) -> some View {
        if isActive {
            content.padding(bleed).drawingGroup().padding(-bleed)
        } else {
            content
        }
    }
}
