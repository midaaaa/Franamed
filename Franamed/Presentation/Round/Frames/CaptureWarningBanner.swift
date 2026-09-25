//
//  CaptureWarningBanner.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.09.2026.
//

import SwiftUI

struct CaptureWarningBanner: View {
    private static let slashRed = Color(red: 0.89, green: 0.29, blue: 0.29)

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 34))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Self.slashRed, .white)
            VStack(spacing: 4) {
                Text("Пожалуйста, уберите телефоны")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text("Приятного просмотра")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @MainActor static let hallLight = HallFrameSample.rendering(CaptureWarningBanner())
}

#Preview("Capture warning banner") {
    CaptureWarningBanner()
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(.black)
}
