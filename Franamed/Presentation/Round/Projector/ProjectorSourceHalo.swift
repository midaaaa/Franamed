//
//  ProjectorSourceHalo.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 16.08.2026.
//

import SwiftUI

private struct ProjectorUpperHalfDisk: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = rect.width / 2
        var path = Path()
        path.move(to: center)
        let steps = 48
        for i in 0...steps {
            let angle = Double.pi * (1.0 + Double(i) / Double(steps))
            let point = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

struct ProjectorSourceHalo: View {
    var opacity: Double = 0.8
    var radius: CGFloat = 35
    var edgeBlur: CGFloat = 12
    var sourceGap: CGFloat = 5

    private var spectrum: RadialGradient {
        RadialGradient(
            stops: [
                .init(color: .white, location: 0.0),
                .init(color: .purple, location: 0.14),
                .init(color: .blue, location: 0.32),
                .init(color: .cyan, location: 0.46),
                .init(color: .green, location: 0.6),
                .init(color: .yellow, location: 0.72),
                .init(color: .orange, location: 0.85),
                .init(color: .red, location: 0.96),
                .init(color: .red.opacity(0), location: 1.0),
            ],
            center: .bottom,
            startRadius: 0,
            endRadius: radius
        )
    }

    var body: some View {
        ProjectorUpperHalfDisk()
            .fill(spectrum)
            .mask(ProjectorBeamShape(topWidthFraction: 0.425, bottomWidthFraction: 0.15))
            .blur(radius: edgeBlur)
            .clipped()
            .mask(alignment: .top) {
                GeometryReader { proxy in
                    Rectangle().frame(height: max(0, proxy.size.height - sourceGap))
                }
            }
            .opacity(opacity)
            .blendMode(.screen)
    }
}

#Preview {
    ProjectorSourceHalo()
        .frame(width: 260, height: 80)
        .background(Color.black)
}
