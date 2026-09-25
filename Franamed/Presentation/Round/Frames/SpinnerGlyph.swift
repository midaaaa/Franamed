//
//  SpinnerGlyph.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.09.2026.
//

import SwiftUI

struct SpinnerGlyph: View {
    private static let petals = 8
    private static let hallShare: Float = 0.3

    var body: some View {
        ZStack {
            ForEach(0..<Self.petals, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.4, height: 5)
                    .offset(y: -5.5)
                    .rotationEffect(.degrees(Double(index) * 360 / Double(Self.petals)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @MainActor static let hallLight = HallFrameSample.rendering(SpinnerGlyph())
        .withBrightness(CaptureWarningBanner.hallLight.brightness * hallShare)
}

#Preview("Spinner glyph") {
    SpinnerGlyph()
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(.black)
}
