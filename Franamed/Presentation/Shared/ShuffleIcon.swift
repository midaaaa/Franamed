//
//  ShuffleIcon.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import SwiftUI

struct ShuffleIcon: View {
    let mode: ShuffleMode

    var body: some View {
        Image(systemName: "shuffle")
            .overlay(alignment: .topTrailing) {
                if mode == .smart {
                    Image(systemName: "sparkle")
                        .font(.system(size: 7, weight: .bold))
                        .offset(x: 5, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach(ShuffleMode.allCases, id: \.self) { mode in
            ShuffleIcon(mode: mode)
        }
    }
    .font(.title)
    .padding()
}
