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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ProjectorBeamFill(stripTints: stripTints)
                    .opacity(isFillLit ? 1 : 0)

                ProjectorSourceHalo()

                ProjectorLineSource()
            }
            .frame(width: proxy.size.width * 1.00, height: proxy.size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .opacity(intensity)
        .allowsHitTesting(false)
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
