//
//  Rasterize.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct Rasterize: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.drawingGroup()
        } else {
            content
        }
    }
}
