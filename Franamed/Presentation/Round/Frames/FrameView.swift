//
//  FrameView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct FrameView: View {
    var maxWidth: CGFloat = .infinity

    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: maxWidth)
    }
}
