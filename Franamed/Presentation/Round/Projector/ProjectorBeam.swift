//
//  ProjectorBeam.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 16.08.2026.
//

import SwiftUI

struct ProjectorBeam: View {
    var intensity: Double
    var stripTints: [ProjectorStripTint] = []
    var isFillLit: Bool = true
    var referenceHeight: CGFloat = 0
    var isProtected: Bool = false
    var showsSource: Bool = true

    static let imperceptibleOpacity = 1.0 / 255

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                protectedFill(height: proxy.size.height)
                    .opacity(isFillLit ? 1 : 0)

                if showsSource {
                    ProjectorSourceHalo()
                    ProjectorLineSource()
                }
            }
            .frame(width: proxy.size.width * 1.00, height: proxy.size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .opacity(max(intensity, Self.imperceptibleOpacity))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func protectedFill(height: CGFloat) -> some View {
        if isProtected {
            ProtectedContent(isProtected: true) {
                fill(height: height)
            }
        } else {
            fill(height: height)
        }
    }

    private func fill(height: CGFloat) -> some View {
        let reference = max(referenceHeight, height)

        return Color.clear
            .overlay(alignment: .bottom) {
                ProjectorBeamFill(stripTints: stripTints)
                    .frame(height: reference)
                    .scaleEffect(x: 1, y: scale(from: reference, to: height), anchor: .bottom)
            }
            .mask(alignment: .bottom) {
                Color.clear.overlay(alignment: .bottom) {
                    ProjectorSourceFalloffMask().frame(height: reference)
                }
            }
    }

    private func scale(from reference: CGFloat, to height: CGFloat) -> CGFloat {
        guard reference > 0 else { return 1 }
        return max(0, height) / reference
    }
}

#Preview("Bright") {
    ProjectorBeam(intensity: 1)
        .frame(height: 160)
        .background(Color.black)
}

#Preview("Dim") {
    ProjectorBeam(intensity: 0.35)
        .frame(height: 160)
        .background(Color.black)
}

#Preview("Off") {
    ProjectorBeam(intensity: 0)
        .frame(height: 160)
        .background(Color.black)
}

#Preview("Tinted (color sampled)") {
    ProjectorBeam(
        intensity: 1,
        stripTints: (0..<14).map { index in
            let hue = Double(index) / 14
            let brightness = 0.5 + 0.3 * sin(Double(index))
            return ProjectorStripTint(
                color: Color(hue: hue, saturation: 0.6, brightness: 0.8),
                brightness: brightness
            )
        }
    )
    .frame(height: 160)
    .background(Color.black)
}
