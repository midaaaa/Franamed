//
//  FrameView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct FrameView: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
